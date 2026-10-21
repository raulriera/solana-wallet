import CryptoKit
import Encoding
import Foundation
import ModularArithmetic
@testable import Privacy
@testable import RPC
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

/// Public-fixture accounts with their private-balance keys, the registry records and deposits that a local provider
/// returns for them, and their transactions' outcomes and proof requests.
///
/// Records and deposits are built from the account's keys as the user-registry and shielded-pool programs write them.
enum PrivateBalanceFixtures {
    /// The recovery identity of every fixture account.
    static let recoveryID = UUID(uuidString: "2C4B8E7A-3F61-4D0B-9E25-6A7D1C3B5F80")!

    /// A registry read that finds no record.
    static let unregistered = #"{"context":{"slot":7},"value":[null]}"#

    /// The published recovery that every fixture account comes from.
    /// - Returns: The public test phrase without a BIP-39 passphrase.
    /// - Throws: A validation error, which doesn't happen.
    static func recovery() throws -> Recovery {
        Recovery(phrase: try RecoveryPhrase(PublicWallet.words), passphrase: "")
    }

    /// Recovery storage that holds the published recovery.
    /// - Returns: Read-only storage with the fixture recovery under ``recoveryID``.
    /// - Throws: A validation error, which doesn't happen.
    static func recoveryStore() throws -> SecurityRecoveryStore {
        SecurityRecoveryStore(records: [recoveryID: try recovery()])
    }

    /// Derives a fixture account at `m/44'/501'/i'/0'`.
    /// - Parameter index: The account index i.
    /// - Returns: The account with its derived address.
    /// - Throws: A derivation or test prerequisite error.
    static func account(index: UInt32 = 0) async throws -> widgets.Account {
        let recovery = try recovery()
        let path = try DerivationPath("m/44'/501'/\(index)'/0'")
        let derived = try #require(try await Wallet().accounts(for: recovery.phrase, passphrase: recovery.passphrase,
                                                               paths: [path]).first)
        return widgets.Account(id: UUID(), recoveryID: recoveryID, address: try Address(derived.address), path: path)
    }

    /// Derives a fixture account's private-balance keys as Wallet does.
    /// - Parameter account: A fixture account.
    /// - Returns: The keys that enabling the account saves.
    /// - Throws: A derivation error.
    static func keys(for account: widgets.Account) async throws -> PrivateBalanceKeyRecord {
        let recovery = try recovery()
        return PrivateBalanceKeyRecord(try await Wallet().privateBalanceKeys(
            using: recovery.phrase, expectedAddress: account.address.value, passphrase: recovery.passphrase,
            path: account.path
        ))
    }

    /// Creates random keys for an address, such as the keys another app registered.
    /// - Parameter address: The account's address.
    /// - Returns: Keys that differ from the fixture account's.
    /// - Throws: A validation error, which doesn't happen.
    static func otherKeys(for address: Address) throws -> ShieldedAccount {
        try ShieldedAccount(signingAddress: address, nullifierSecret: SymmetricKey(size: SymmetricKeySize(bitCount: 248)),
                            viewingKey: P256.KeyAgreement.PrivateKey())
    }

    /// Creates a devnet transaction's settled outcome.
    /// - Parameters:
    ///   - outcome: Whether it succeeded, failed, or was dropped.
    ///   - signature: The transaction's signature.
    /// - Returns: The confirmation.
    static func confirmation(_ outcome: widgets.Confirmation.Outcome,
                             signature: String = "private") -> widgets.Confirmation {
        widgets.Confirmation(submission: Submission(signature: signature, network: .devnet, lastValidBlockHeight: 1), slot: 5,
                             outcome: outcome)
    }

    /// Counts the proof requests sent so far.
    /// - Parameter responses: The local responses that recorded the requests.
    /// - Returns: The number of requests on the prover's route.
    static func proofRequests(of responses: HTTPResponses) async -> Int {
        await responses.requests.count { $0.url?.path().hasSuffix("/prove") == true }
    }

    /// A registry read that finds the record publishing an account's keys.
    /// - Parameter account: The keys that the record publishes.
    /// - Returns: The `getMultipleAccounts` result.
    /// - Throws: A derivation error, which doesn't happen.
    static func registry(publishing account: ShieldedAccount) throws -> String {
        #"{"context":{"slot":7},"value":[\#(try registryRecord(publishing: account))]}"#
    }

    /// The account of the registry record that publishes an account's keys.
    ///
    /// The record holds the discriminator 1, the owner, the canonical bump, no P-256 owner, the nullifier public key,
    /// the compressed viewing public key, and no merging, padded with zeros to 134 bytes, with 1,823,520 lamports.
    /// - Parameter account: The keys that the record publishes.
    /// - Returns: The account's JSON object.
    /// - Throws: A derivation error, which doesn't happen.
    static func registryRecord(publishing account: ShieldedAccount) throws -> String {
        let owner = account.signingAddress.bytes
        var data = [1] + owner + [try UserRegistry.record(of: account.signingAddress).bump, 0]
        data += account.nullifierKey.publicKey.bigEndianBytes
        data += Array(account.viewingKey.publicKey.compressedRepresentation) + [0]
        data += [UInt8](repeating: 0, count: 134 - data.count)
        return #"{"owner":"\#(try UserRegistry.program.value)","lamports":1823520,"executable":false,"#
            + #""data":["\#(Data(data).base64EncodedString())","base64"]}"#
    }

    /// A proofless deposit of SOL to an account, as an encrypted-output row of a tag read.
    ///
    /// The payload is the plaintext encoding: the tag 0, the little-endian length of the rest, the proofless scheme 0,
    /// the owner hash, the program's blinding for the output's position, SOL's zero mint, the amount, five absent
    /// options, and no memo.
    /// - Parameters:
    ///   - lamports: The deposited amount.
    ///   - account: The receiving account.
    ///   - leafIndex: The output's position in tree 1.
    /// - Returns: The row's JSON object.
    /// - Throws: A validation error, which doesn't happen.
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

    /// The UTXO root position of every fixed inclusion proof.
    static let utxoRootIndex: UInt16 = 3

    /// The nullifier root position of every fixed non-inclusion proof.
    static let nullifierRootIndex: UInt16 = 4

    /// Answers a proof's requests: the indexer's proof reads with fixed proofs, by result value, and the prover's
    /// complete route with fixed curve points and the shape's proving key, by body.
    ///
    /// Proofs have zero paths, the UTXO root 1, and the nullifier root 2, with each nullifier between 0 and r - 1. The
    /// points aren't a valid proof, which only a validator's pairing check would notice.
    /// - Parameter request: A `getMerkleProofs` or `getNonInclusionProofs` request, or a request on `prove`.
    /// - Returns: The JSON-RPC result value, or the prover's response body.
    /// - Throws: A test prerequisite error for a malformed request.
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

    /// Creates the proof request of a withdrawal that spends one of an account's UTXOs in tree 1, with the fixed proofs.
    /// - Parameter account: The spending account.
    /// - Returns: The request that the account's client sends to the prover.
    /// - Throws: A planning error, which doesn't happen.
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

    /// Creates the fixed inclusion proof of a UTXO hash.
    /// - Parameter leaf: The 32-byte UTXO hash.
    /// - Returns: The proof at leaf 0 with a zero path, under root 1 at ``utxoRootIndex``.
    /// - Throws: A validation error for a leaf of another length.
    private static func inclusionProof(of leaf: [UInt8]) throws -> MerkleProof {
        try MerkleProof(leaf: leaf, path: Array(repeating: field(0), count: MerkleProof.height), leafIndex: 0, root: field(1),
                        rootIndex: utxoRootIndex)
    }

    /// Creates the fixed non-inclusion proof of a nullifier.
    /// - Parameter nullifier: The 32-byte nullifier.
    /// - Returns: The proof between 0 at position 0 and r - 1, with a zero path, under root 2 at ``nullifierRootIndex``.
    /// - Throws: A validation error for a nullifier of another length.
    private static func nonInclusionProof(of nullifier: [UInt8]) throws -> NonInclusionProof {
        let highest = try #require(FieldHex.decode("0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000000"))
        return try NonInclusionProof(nullifier: nullifier, lowElement: field(0), lowElementIndex: 0, highElement: highest,
                                     path: Array(repeating: field(0), count: NonInclusionProof.height), root: field(2),
                                     rootIndex: nullifierRootIndex)
    }

    /// A 32-byte big-endian field element of a small value.
    /// - Parameter value: The value's last byte.
    /// - Returns: Thirty-one zero bytes followed by `value`.
    private static func field(_ value: UInt8) -> [UInt8] { Array(repeating: 0, count: 31) + [value] }

    /// Encodes an integer's little-endian bytes.
    /// - Parameter value: The integer.
    /// - Returns: The bytes, least significant first.
    private static func littleEndian<Value: FixedWidthInteger>(_ value: Value) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian, Array.init)
    }
}
