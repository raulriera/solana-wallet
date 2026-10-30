import CryptoKit
import Encoding
import Foundation
import ModularArithmetic
import Observation
@testable import Privacy
@testable import RPC
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

enum PrivateBalanceFixtures {
    static let recoveryID = UUID(uuidString: "2C4B8E7A-3F61-4D0B-9E25-6A7D1C3B5F80")!

    static let unregistered = #"{"context":{"slot":7},"value":[null]}"#

    static func recovery() throws -> Recovery {
        try PublicWallet.recovery()
    }

    static func recoveryStore() throws -> SecurityRecoveryStore {
        SecurityRecoveryStore(records: [recoveryID: try recovery()])
    }

    static func account(index: UInt32 = 0) async throws -> widgets.Account {
        try await PublicWallet.account(index: index, recoveryID: recoveryID)
    }

    static func keys(for account: widgets.Account) async throws -> PrivateBalanceKeyRecord {
        let recovery = try recovery()
        return PrivateBalanceKeyRecord(try await Wallet().privateBalanceKeys(
            using: recovery.phrase, expectedAddress: account.address.value, passphrase: recovery.passphrase,
            path: account.path
        ))
    }

    static func otherKeys(for address: Address) throws -> ShieldedAccount {
        try ShieldedAccount(signingAddress: address, nullifierSecret: SymmetricKey(size: SymmetricKeySize(bitCount: 248)),
                            viewingKey: P256.KeyAgreement.PrivateKey())
    }

    static func confirmation(_ outcome: widgets.Confirmation.Outcome,
                             signature: String = "private") -> widgets.Confirmation {
        widgets.Confirmation(submission: Submission(signature: signature, network: .devnet, lastValidBlockHeight: 1), slot: 5,
                             outcome: outcome)
    }

    static func preparedDeposit(_ lamports: UInt64, from account: widgets.Account) -> PreparedPrivateTransaction {
        PreparedPrivateTransaction(instructions: [], account: account, network: .devnet, effect: .deposit(lamports),
                                   registers: false, authorities: [.account(account)])
    }

    @MainActor
    static func pendingDeposit(of account: widgets.Account, responses: HTTPResponses = HTTPResponses.privateNotes(),
                               transactions: TransactionStore = .unused, pollInterval: Duration = .seconds(30),
                               followUpInterval: Duration = .seconds(3))
        async throws -> (store: PrivateBalanceStore, notes: StoredValue<PrivateBalances.Notes>) {
        let keys = StoredValue([account.address.value: try await keys(for: account)])
        let notes = StoredValue<PrivateBalances.Notes>([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
        let balances = PrivateBalances.inMemory(keys: keys, notes: notes, recovery: try recoveryStore(),
                                                responses: HTTPResponses.privateNotes())
        _ = try await balances.complete(preparedDeposit(1_000_000, from: account), with: confirmation(.succeeded))
        let store = try PrivateBalanceStore.fixture(responses, keys: keys, notes: notes,
                                                    transactions: transactions, pollInterval: pollInterval,
                                                    followUpInterval: followUpInterval)
        return (store, notes)
    }

    enum Balance: Sendable {
        case available
        case pending
        case unregistered
    }

    @MainActor
    static func store(holding balance: Balance, of account: widgets.Account,
                      transactions: TransactionStore = .unused) async throws -> PrivateBalanceStore {
        let record = try await keys(for: account)
        let keys = StoredValue([account.address.value: record])
        switch balance {
        case .available:
            let shielded = try record.shieldedAccount(for: account.address)
            let responses = HTTPResponses.privateNotes(registry: [try registry(publishing: shielded)],
                                                       deposits: [try deposit(1_000_000, to: shielded, leafIndex: 4)])
            return try PrivateBalanceStore.fixture(responses, keys: keys, transactions: transactions)
        case .pending:
            return try await pendingDeposit(of: account, transactions: transactions).store
        case .unregistered:
            return try PrivateBalanceStore.fixture(HTTPResponses.privateNotes(registry: [unregistered]), keys: keys,
                                                   transactions: transactions)
        }
    }

    @MainActor
    static func read(_ account: widgets.Account, in store: PrivateBalanceStore) async throws -> WalletPrivateBalance {
        await store.refresh(account, on: .devnet)
        return try #require(store.balance(for: account, on: .devnet))
    }

    @MainActor
    static func status(of account: widgets.Account, in store: PrivateBalanceStore,
                       becomes status: PrivateBalanceStatus) async throws {
        for await read in Observations({ store.balance(for: account, on: .devnet)?.status }) where read == status {
            return
        }
        try Task.checkCancellation()
    }

    static func registryReads(of responses: HTTPResponses) async -> Int {
        await responses.requests.count { (try? $0.jsonBody()["method"] as? String) == GetMultipleAccounts.method }
    }

    static func proofRequests(of responses: HTTPResponses) async -> Int {
        await responses.requests.count { $0.url?.path().hasSuffix("/prove") == true }
    }

    static func registry(publishing account: ShieldedAccount) throws -> String {
        #"{"context":{"slot":7},"value":[\#(try registryRecord(publishing: account))]}"#
    }

    static func registryRecord(publishing account: ShieldedAccount) throws -> String {
        let owner = account.signingAddress.bytes
        var data = [1] + owner + [try UserRegistry.record(of: account.signingAddress).bump, 0]
        data += account.nullifierKey.publicKey.bigEndianBytes
        data += Array(account.viewingKey.publicKey.compressedRepresentation) + [0]
        data += [UInt8](repeating: 0, count: 134 - data.count)
        return #"{"owner":"\#(try UserRegistry.program.value)","lamports":1823520,"executable":false,"#
            + #""data":["\#(Data(data).base64EncodedString())","base64"]}"#
    }

    static func deposit(_ lamports: UInt64, to account: ShieldedAccount, leafIndex: UInt64) throws -> String {
        let treeID: UInt16 = 1
        let owner = try account.recipient.owner
        let blinding = ShieldedPool.depositBlinding(tree: try ShieldedPool.tree(id: treeID), leafIndex: leafIndex)
        let mint = [UInt8](repeating: 0, count: 32)
        let hash = UTXO(owner: owner, mint: mint, amount: lamports, blinding: blinding, treeID: treeID).hash
        let body = [0] + owner.bigEndianBytes + blinding.bigEndianBytes + mint + littleEndian(lamports)
            + [UInt8](repeating: 0, count: 5) + [0]
        let payload = [0] + littleEndian(UInt32(body.count)) + body
        let output = #"{"viewTag":"\#(account.signingAddress.value)","outputContext":{"hash":"\#(Base58.encode(hash.bigEndianBytes))","#
            + #""treeId":\#(treeID),"leafIndex":\#(leafIndex)},"payload":"\#(Data(payload).base64EncodedString())"}"#
        let signature = Base58.encode([UInt8](repeating: UInt8(truncatingIfNeeded: leafIndex + 1), count: 64))
        return #"{"slot":3,"txSignature":"\#(signature)","outputSlot":\#(output),"txViewingPk":null,"salt":null}"#
    }

    static let utxoRootIndex: UInt16 = 3

    static let nullifierRootIndex: UInt16 = 4

    static func proof(answering request: URLRequest) throws -> String {
        let body = try request.jsonBody()
        guard let method = body["method"] as? String else {
            let shape = Shape(inputs: try #require(body["nInputs"] as? Int), outputs: try #require(body["nOutputs"] as? Int))
            let point = ["0x1", "0x2"]
            return try HTTPResponses.json([
                "ar": point, "bs": [point, point], "krs": point,
                "provingKeySha256": shape.provingKeyDigest.map { String(format: "%02x", $0) }.joined(),
            ] as [String: Any])
        }
        let params = try #require(body["params"] as? [String: Any])
        let tree = try #require(params["treeAccount"] as? String)
        let leaves = try #require(params["leaves"] as? [String]).map { try #require(Base58.decode($0, byteCount: 32)) }
        let proofs: [[String: Any]] = try leaves.map { leaf in
            let context: [String: Any] = ["treeType": method == GetMerkleProofs.method ? 1 : 2, "tree": tree]
            if method == GetMerkleProofs.method {
                let proof = try inclusionProof(of: leaf)
                return ["leaf": Base58.encode(proof.leaf), "merkleContext": context, "path": proof.path.map(Base58.encode),
                        "leafIndex": proof.leafIndex, "root": Base58.encode(proof.root), "rootSeq": 1, "rootIndex": proof.rootIndex]
            }
            let proof = try nonInclusionProof(of: leaf)
            return ["leaf": Base58.encode(proof.nullifier), "merkleContext": context, "path": proof.path.map(Base58.encode),
                    "lowElement": Base58.encode(proof.lowElement), "lowElementIndex": proof.lowElementIndex,
                    "highElement": Base58.encode(proof.highElement), "highElementIndex": 1, "root": Base58.encode(proof.root),
                    "rootSeq": 1, "rootIndex": proof.rootIndex]
        }
        return try HTTPResponses.json(["context": ["slot": 1], "proofs": proofs] as [String: Any])
    }

    static func proofRequest(spending account: ShieldedAccount) throws -> TransferProofRequest {
        var generator = SystemRandomNumberGenerator()
        let utxo = UTXO(owner: try account.recipient.owner, mint: [UInt8](repeating: 0, count: 32), amount: 10,
                        blinding: Poseidon.Element(UInt64(7)), treeID: 1)
        let plan = try TransactPlan(spending: [utxo], sender: account, transfer: nil,
                                    withdrawal: ExternalData.Withdrawal(recipient: account.signingAddress, lamports: 10),
                                    outputTreeID: 1, using: &generator)
        let tree = try TransactPlan.TreeWitness(
            treeID: 1, inclusionProofs: plan.inputs.filter { $0.utxo != nil }.map { try inclusionProof(of: $0.hash.bigEndianBytes) },
            nonInclusionProofs: plan.inputs.map { try nonInclusionProof(of: $0.nullifier.bigEndianBytes) }
        )
        return try plan.proofRequest(nullifierKey: account.nullifierKey, trees: [tree])
    }

    private static func inclusionProof(of leaf: [UInt8]) throws -> MerkleProof {
        try MerkleProof(leaf: leaf, path: Array(repeating: field(0), count: MerkleProof.height), leafIndex: 0, root: field(1),
                        rootIndex: utxoRootIndex)
    }

    private static func nonInclusionProof(of nullifier: [UInt8]) throws -> NonInclusionProof {
        let highest = try #require(FieldHex.decode("0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000000"))
        return try NonInclusionProof(nullifier: nullifier, lowElement: field(0), lowElementIndex: 0, highElement: highest,
                                     path: Array(repeating: field(0), count: NonInclusionProof.height), root: field(2),
                                     rootIndex: nullifierRootIndex)
    }

    private static func field(_ value: UInt8) -> [UInt8] { Array(repeating: 0, count: 31) + [value] }

    private static func littleEndian<Value: FixedWidthInteger>(_ value: Value) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian, Array.init)
    }
}
