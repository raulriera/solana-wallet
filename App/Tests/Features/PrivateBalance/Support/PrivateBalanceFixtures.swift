import CryptoKit
import Encoding
import Foundation
import ModularArithmetic
import Observation
import Portfolio
import Testing
import Transactions
import Vault
import Wallet
@testable import Privacy
@testable import RPC
@testable import widgets

enum PrivateBalanceFixtures {
    static let recoveryID = UUID(uuidString: "2C4B8E7A-3F61-4D0B-9E25-6A7D1C3B5F80")!

    static let unregistered = AccountReplies.accounts([nil])

    nonisolated static let solHolding = Holding(asset: .nativeSOL, balance: TokenAmount(lamports: 2_000_000_000),
                                                imageURL: nil, valuation: nil)

    static func recoveryStore() throws -> SecurityRecoveryStore {
        SecurityRecoveryStore(records: [recoveryID: try ThrowawayWallet.recovery()])
    }

    static func account(index: UInt32 = 0) async throws -> widgets.Account {
        try await ThrowawayWallet.account(index: index, recoveryID: recoveryID)
    }

    static func customRPC() throws -> RPCSettings.Provider {
        .custom(try #require(URL(string: "https://rpc.example.com")))
    }

    static func keys(for account: widgets.Account) async throws -> PrivateBalanceKeyRecord {
        let recovery = try ThrowawayWallet.recovery()
        return PrivateBalanceKeyRecord(try await Wallet().privateBalanceKeys(
            using: recovery.phrase, expectedAddress: account.address.value, passphrase: recovery.passphrase,
            path: account.path
        ))
    }

    static func otherKeys(for address: Address) throws -> ShieldedAccount {
        try ShieldedAccount(signingAddress: address, nullifierSecret: SymmetricKey(size: SymmetricKeySize(bitCount: 248)),
                            viewingKey: Curve25519.KeyAgreement.PrivateKey())
    }

    static func outcome(_ status: TransactionOutcome.Status, signature: String = "private") -> TransactionOutcome {
        TransactionOutcome(signature: signature, network: .devnet, lastValidBlockHeight: 1, status: status)
    }

    static func preparedDeposit(_ amount: UInt64, of asset: PrivateAsset,
                                from account: widgets.Account) -> PreparedPrivateTransaction {
        PreparedPrivateTransaction(instructions: [], account: account, network: .devnet, effect: .deposit(amount, of: asset),
                                   registers: false, authorities: [.account(account)])
    }

    @MainActor
    static func pendingDeposit(of account: widgets.Account, responses: HTTPResponses = HTTPResponses.privateNotes(),
                               transactions: TransactionStore = .unused, clock: ManualClock = ManualClock())
        async throws -> (store: PrivateBalanceStore, notes: StoredValue<PrivateBalances.Notes>) {
        let keys = StoredValue([account.address.value: try await keys(for: account)])
        let notes = StoredValue<PrivateBalances.Notes>([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
        let balances = PrivateBalances.inMemory(keys: keys, notes: notes, recovery: try recoveryStore(),
                                                responses: HTTPResponses.privateNotes())
        _ = try await balances.complete(preparedDeposit(1_000_000, of: .nativeSOL, from: account), with: outcome(.succeeded))
        let store = try PrivateBalanceStore.fixture(responses, keys: keys, notes: notes,
                                                    transactions: transactions, clock: clock)
        return (store, notes)
    }

    enum Balance: Sendable {
        case available
        case availableToken
        case pending
        case unregistered

        var asset: PrivateAsset { self == .availableToken ? .token(.devnetUSDC) : .nativeSOL }
    }

    @MainActor
    static func store(holding balance: Balance, of account: widgets.Account,
                      transactions: TransactionStore = .unused) async throws -> PrivateBalanceStore {
        let record = try await keys(for: account)
        let keys = StoredValue([account.address.value: record])
        switch balance {
        case .available, .availableToken:
            let shielded = try record.shieldedAccount(for: account.address)
            let deposit = try deposit(1_000_000, to: shielded, leafIndex: 4, of: balance.asset)
            let responses = HTTPResponses.privateNotes(registry: [try registry(publishing: shielded)], deposits: [deposit])
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

    static func nonTreeAccountReads(of responses: HTTPResponses) async -> Int {
        let trees = (try? ShieldedPool.tree(id: 1).value).map { [$0] }
        return await responses.requests.count { request in
            (try? request.rpcMethod) == GetMultipleAccounts.method && (try? requestedAddresses(request)) != trees
        }
    }

    static func proofRequests(of responses: HTTPResponses) async -> Int {
        await responses.requests.count { $0.url?.path().hasSuffix("/indexed") == true }
    }

    static func registry(publishing account: ShieldedAccount) throws -> String {
        AccountReplies.accounts([try registryRecord(publishing: account)])
    }

    static func registryRecord(publishing account: ShieldedAccount) throws -> String {
        let owner = account.signingAddress.bytes
        var data = [1] + owner + [try UserRegistry.record(of: account.signingAddress).bump]
        data += account.nullifierKey.publicKey.bigEndianBytes
        data += Array(account.viewingKey.publicKey.taggedRepresentation) + [0]
        return AccountReplies.account(owner: try UserRegistry.address.value, lamports: 1_586_880, data: data)
    }

    static func deposit(_ amount: UInt64, to account: ShieldedAccount, leafIndex: UInt64, tree treeID: UInt16 = 1,
                        of asset: PrivateAsset) throws -> String {
        let utxo = try utxo(amount, of: account, leafIndex: leafIndex, treeID: treeID, asset: asset)
        var body = [0] + utxo.owner.bigEndianBytes + utxo.blinding.bigEndianBytes + utxo.asset.mintBytes
        body.append(littleEndian: amount)
        body += [UInt8](repeating: 0, count: 5) + [0]
        var payload: [UInt8] = [0]
        payload.append(littleEndian: UInt32(body.count))
        payload += body
        let output = IndexerReplies.output(viewTag: account.signingAddress.value, hash: Base58.encode(utxo.hash.bigEndianBytes),
                                           treeID: utxo.treeID, leafIndex: leafIndex,
                                           payload: Data(payload).base64EncodedString())
        return IndexerReplies.match(signature: RedeemCodeFixtures.signature(ofDepositAt: leafIndex), slot: 3,
                                    output: output)
    }

    static func spend(of lamports: UInt64, to account: ShieldedAccount, leafIndex: UInt64) throws -> String {
        let utxo = try utxo(lamports, of: account, leafIndex: leafIndex, treeID: 1, asset: .nativeSOL)
        let nullifier = Base58.encode(utxo.nullifier(using: account.nullifierKey).bigEndianBytes)
        let signature = Base58.encode([UInt8](repeating: UInt8(truncatingIfNeeded: leafIndex + 101), count: 64))
        return IndexerReplies.transaction(signature: signature, slot: 4, nullifiers: [nullifier])
    }

    static func proofRequest(spending account: ShieldedAccount) throws -> IndexedTransferProofRequest {
        var generator = SystemRandomNumberGenerator()
        let utxo = UTXO(owner: try account.recipient.owner, asset: .nativeSOL, amount: 10,
                        blinding: Poseidon.Element(UInt64(7)), treeID: 1)
        let plan = try TransactPlan(spending: [utxo], of: .nativeSOL, sender: account, transfer: nil,
                                    withdrawal: ExternalData.Withdrawal(recipient: account.signingAddress, amount: 10, asset: .nativeSOL),
                                    outputTreeID: 1, using: &generator)
        return try plan.proofRequest(nullifierKey: account.nullifierKey)
    }

    private static func utxo(_ amount: UInt64, of account: ShieldedAccount, leafIndex: UInt64, treeID: UInt16,
                             asset: PrivateAsset) throws -> UTXO {
        let blinding = ShieldedPool.depositBlinding(tree: try ShieldedPool.tree(id: treeID), leafIndex: leafIndex)
        return UTXO(owner: try account.recipient.owner, asset: asset, amount: amount,
                    blinding: blinding, treeID: treeID)
    }
}
