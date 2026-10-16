import Foundation
import Privacy
@testable import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

/// Verifies enabling, refreshing, and removing private balances through the real provider client and Helius client with
/// local registry and indexer responses, in in-memory storage.
@Suite(.timeLimit(.minutes(1)))
struct PrivateBalancesTests {
    /// Enabling an unregistered account derives its keys from recovery and keeps them by address, without notes.
    @Test
    func `Enabling keeps the keys of an unregistered account`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let recovery = try PrivateBalanceFixtures.recoveryStore()
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered])
        let keys = StoredValue<PrivateBalances.Keys>()
        let notes = StoredValue<PrivateBalances.Notes>()

        try await Self.balances(responses, recovery: recovery, keys: keys, notes: notes).enable(account, on: .devnet)

        #expect(await keys.value == [account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        #expect(await notes.value == nil)
        #expect(await recovery.reads == [PrivateBalanceFixtures.recoveryID])
        #expect(try await Self.methods(of: responses) == [GetMultipleAccounts.method])
    }

    /// Enabling adds an account's keys beside the keys already kept for other accounts.
    @Test
    func `Enabling keeps other accounts' keys`() async throws {
        async let derivedFirst = PrivateBalanceFixtures.account(index: 0)
        async let derivedSecond = PrivateBalanceFixtures.account(index: 1)
        let (first, second) = try await (derivedFirst, derivedSecond)
        let firstKeys = try await PrivateBalanceFixtures.keys(for: first)
        let keys = StoredValue<PrivateBalances.Keys>([first.address.value: firstKeys])
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered])

        try await Self.balances(responses, keys: keys).enable(second, on: .devnet)

        #expect(await keys.value == [first.address.value: firstKeys,
                                     second.address.value: try await PrivateBalanceFixtures.keys(for: second)])
    }

    /// Off a network with private balances, enabling keeps the keys without reading a registry that doesn't exist there.
    @Test
    func `Enabling off devnet checks no registration`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes()
        let keys = StoredValue<PrivateBalances.Keys>()

        try await Self.balances(responses, keys: keys).enable(account, on: .mainnet)

        #expect(await keys.value?[account.address.value] != nil)
        #expect(await responses.requests.isEmpty)
    }

    /// Enabling an account whose keys are already registered keeps its keys and its empty notes entry, so a refresh
    /// never checks registration again.
    @Test
    func `Enabling an account registered with its own keys keeps its keys and notes entry`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let registry = try PrivateBalanceFixtures.registry(publishing: record.shieldedAccount(for: account.address))
        let responses = HTTPResponses.privateNotes(registry: [registry])
        let keys = StoredValue<PrivateBalances.Keys>()
        let notes = StoredValue<PrivateBalances.Notes>()

        try await Self.balances(responses, keys: keys, notes: notes).enable(account, on: .devnet)

        #expect(await keys.value == [account.address.value: record])
        #expect(await notes.value == [PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
        #expect(try await Self.methods(of: responses) == [GetMultipleAccounts.method])
    }

    /// A custom RPC serves only mainnet, so enabling on devnet keeps the keys without a registration check; a later
    /// refresh checks it.
    @Test
    func `Enabling with a custom RPC off mainnet keeps the keys unchecked`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes()
        let keys = StoredValue<PrivateBalances.Keys>()
        let notes = StoredValue<PrivateBalances.Notes>()

        try await Self.balances(responses, provider: try Self.customRPC(), keys: keys, notes: notes)
            .enable(account, on: .devnet)

        #expect(await keys.value == [account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        #expect(await notes.value == nil)
        #expect(await responses.requests.isEmpty)
    }

    /// An account at a path without private-balance keys is rejected before the person is asked to authenticate.
    @Test
    func `Enabling an account at another path prompts nothing and throws`() async throws {
        let fixture = try await PrivateBalanceFixtures.account()
        let account = widgets.Account(id: UUID(), recoveryID: PrivateBalanceFixtures.recoveryID, address: fixture.address,
                                      path: try DerivationPath("m/44'/501'/0'"))
        let recovery = try PrivateBalanceFixtures.recoveryStore()
        let responses = HTTPResponses.privateNotes()
        let keys = StoredValue<PrivateBalances.Keys>()

        await #expect(throws: PrivateBalanceError.unsupportedAccount) {
            try await Self.balances(responses, recovery: recovery, keys: keys).enable(account, on: .devnet)
        }
        #expect(await recovery.reads.isEmpty)
        #expect(await keys.value == nil)
        #expect(await responses.requests.isEmpty)
    }

    /// A reset while enabling waits on the registry leaves no keys or notes once enabling finishes.
    @Test
    func `A reset during enabling leaves no keys`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let gate = Suspension()
        let responses = HTTPResponses.privateNotes(
            registry: [try PrivateBalanceFixtures.registry(publishing: record.shieldedAccount(for: account.address))],
            gate: gate, heldMethod: GetMultipleAccounts.method
        )
        let keys = StoredValue<PrivateBalances.Keys>()
        let notes = StoredValue<PrivateBalances.Notes>()
        let balances = try Self.balances(responses, keys: keys, notes: notes)

        let enabling = Task { try await balances.enable(account, on: .devnet) }
        await gate.waitUntilStarted()
        try await balances.removeAll()
        gate.resume()

        await #expect(throws: CancellationError.self) { try await enabling.value }
        #expect(await keys.value == nil)
        #expect(await notes.value == nil)
    }

    /// Keys that another app registered for the account are rejected, and nothing is saved.
    @Test
    func `Enabling rejects an account registered with other keys`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let other = try PrivateBalanceFixtures.otherKeys(for: account.address)
        let responses = HTTPResponses.privateNotes(registry: [try PrivateBalanceFixtures.registry(publishing: other)])
        let keys = StoredValue<PrivateBalances.Keys>()

        await #expect(throws: PrivateBalanceError.registeredWithOtherKeys) {
            try await Self.balances(responses, keys: keys).enable(account, on: .devnet)
        }
        #expect(await keys.value == nil)
    }

    /// A recovery read that fails, such as a cancelled prompt, fails enabling before any request or save.
    @Test
    func `Enabling saves nothing when recovery can't be read`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes()
        let keys = StoredValue<PrivateBalances.Keys>()

        await #expect(throws: CancellationError.self) {
            try await Self.balances(responses, recovery: SecurityRecoveryStore(readError: CancellationError()), keys: keys)
                .enable(account, on: .devnet)
        }
        #expect(await keys.value == nil)
        #expect(await responses.requests.isEmpty)
    }

    /// Without keys, private balances are off, and nothing is requested.
    @Test
    func `Refreshing an account without keys is off`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes()

        #expect(try await Self.balances(responses).refresh(account, on: .devnet) == .off)
        #expect(await responses.requests.isEmpty)
    }

    /// Off a network with private balances, a refresh is unavailable, and nothing is read.
    @Test
    func `Refreshing off devnet is unavailable`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes()
        let keys = StoredValue<PrivateBalances.Keys>([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])

        #expect(try await Self.balances(responses, keys: keys).refresh(account, on: .mainnet) == .unavailable)
        #expect(await responses.requests.isEmpty)
    }

    /// A first refresh checks registration once, syncs from the start, and saves the notes; a later refresh resumes
    /// from the saved notes without checking registration again.
    @Test
    func `A registered account syncs and saves its notes, checking registration once`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let shielded = try record.shieldedAccount(for: account.address)
        let responses = HTTPResponses.privateNotes(
            registry: [try PrivateBalanceFixtures.registry(publishing: shielded)],
            deposits: [try PrivateBalanceFixtures.deposit(1_000_000, to: shielded, leafIndex: 4)]
        )
        let notes = StoredValue<PrivateBalances.Notes>()
        let balances = try Self.balances(responses, keys: StoredValue([account.address.value: record]), notes: notes)
        let id = PrivateBalances.noteID(of: account, on: .devnet)

        let first = try await balances.refresh(account, on: .devnet)
        let saved = await notes.value?[id]
        let later = try await balances.refresh(account, on: .devnet)

        #expect(first == .lamports(1_000_000))
        #expect(later == .lamports(1_000_000))
        #expect(saved?.lamports == 1_000_000)
        #expect(await notes.value?[id] == saved)
        #expect(try await Self.methods(of: responses).filter { $0 == GetMultipleAccounts.method }.count == 1)
        let tagReads = try await responses.requests.filter { try $0.rpcMethod == GetShieldedTransactionsByTags.method }
        let cursors = try tagReads.map { try #require($0.jsonBody()["params"] as? [String: Any])["cursor"] as? String }
        #expect(cursors == [nil, HTTPResponses.indexerPosition])
    }

    /// An unregistered account reads no notes and saves no notes entry.
    @Test
    func `An unregistered account reads no notes`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses([GetMultipleAccounts.method: [PrivateBalanceFixtures.unregistered]])
        let notes = StoredValue<PrivateBalances.Notes>()
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])

        #expect(try await Self.balances(responses, keys: keys, notes: notes).refresh(account, on: .devnet) == .unregistered)
        #expect(await notes.value == nil)
        #expect(try await Self.methods(of: responses) == [GetMultipleAccounts.method])
    }

    /// An account registered with other keys fails the refresh instead of showing a balance.
    @Test
    func `A refresh of an account registered with other keys fails`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let other = try PrivateBalanceFixtures.otherKeys(for: account.address)
        let responses = HTTPResponses([GetMultipleAccounts.method: [try PrivateBalanceFixtures.registry(publishing: other)]])
        let notes = StoredValue<PrivateBalances.Notes>()
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])

        await #expect(throws: PrivateBalanceError.registeredWithOtherKeys) {
            try await Self.balances(responses, keys: keys, notes: notes).refresh(account, on: .devnet)
        }
        #expect(await notes.value == nil)
    }

    /// A selected provider that doesn't read private notes makes the balance unavailable and keeps the saved notes.
    @Test
    func `A provider without private notes is unavailable`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes()
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()])
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])

        let status = try await Self.balances(responses, provider: .solana, keys: keys, notes: notes).refresh(account, on: .devnet)

        #expect(status == .unavailable)
        #expect(await notes.value == [id: NoteSyncState()])
        #expect(await responses.requests.isEmpty)
    }

    /// Solana's public RPC reads the registry but not private notes: a registered account keeps its empty notes entry,
    /// and its balance is unavailable.
    @Test
    func `Solana's public RPC without a notes entry is unavailable`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let registry = try PrivateBalanceFixtures.registry(publishing: record.shieldedAccount(for: account.address))
        let responses = HTTPResponses.privateNotes(registry: [registry])
        let notes = StoredValue<PrivateBalances.Notes>()
        let balances = try Self.balances(responses, provider: .solana, keys: StoredValue([account.address.value: record]),
                                         notes: notes)

        #expect(try await balances.refresh(account, on: .devnet) == .unavailable)
        #expect(await notes.value == [PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
        #expect(try await Self.methods(of: responses) == [GetMultipleAccounts.method])
    }

    /// A custom RPC serves only mainnet, so on devnet a refresh is unavailable whether or not registration was checked,
    /// and nothing is sent or saved.
    /// - Parameter hasNotes: Whether the account already has a notes entry.
    @Test(arguments: [false, true])
    func `A custom RPC off mainnet is unavailable`(hasNotes: Bool) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes()
        let saved: PrivateBalances.Notes? = hasNotes ? [PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()] : nil
        let notes = StoredValue(saved)
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])

        let status = try await Self.balances(responses, provider: try Self.customRPC(), keys: keys, notes: notes)
            .refresh(account, on: .devnet)

        #expect(status == .unavailable)
        #expect(await notes.value == saved)
        #expect(await responses.requests.isEmpty)
    }

    /// A provider error, such as a rate limit, is thrown instead of a balance, and the saved notes stay.
    @Test
    func `Provider errors fail the refresh and keep the saved notes`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes(error: .http(statusCode: 429, retryAfter: nil))
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()])
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: nil)) {
            try await Self.balances(responses, keys: keys, notes: notes).refresh(account, on: .devnet)
        }
        #expect(await notes.value == [id: NoteSyncState()])
    }

    /// A refresh that starts while another refresh of the same account is reading the indexer shares its sync.
    @Test
    func `Concurrent refreshes of one account share one sync`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let gate = Suspension()
        let responses = HTTPResponses.privateNotes(
            deposits: [try PrivateBalanceFixtures.deposit(42, to: record.shieldedAccount(for: account.address), leafIndex: 1)],
            gate: gate, heldMethod: GetShieldedTransactionsByTags.method
        )
        let notes = StoredValue<PrivateBalances.Notes>([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
        let balances = try Self.balances(responses, keys: StoredValue([account.address.value: record]), notes: notes)

        let first = await Self.startRefresh(of: account, in: balances)
        await gate.waitUntilStarted()
        let second = await Self.startRefresh(of: account, in: balances)
        gate.resume()

        #expect(try await first.value == .lamports(42))
        #expect(try await second.value == .lamports(42))
        #expect(try await Self.methods(of: responses).filter { $0 == GetShieldedTransactionsByTags.method }.count == 1)
    }

    /// A shared sync that failed isn't kept: the next refresh syncs again.
    @Test
    func `A failed shared sync is retried by the next refresh`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let deposit = try PrivateBalanceFixtures.deposit(42, to: record.shieldedAccount(for: account.address), leafIndex: 1)
        let responses = HTTPResponses([
            GetShieldedTransactionsByTags.method: ["null", HTTPResponses.indexerPage([], in: "transactions")],
            GetEncryptedUtxosByTags.method: [HTTPResponses.indexerPage([deposit], in: "matches")],
            GetShieldedTransactionsByNullifiers.method: [HTTPResponses.indexerPage([], in: "transactions")],
        ])
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()])
        let balances = try Self.balances(responses, keys: StoredValue([account.address.value: record]), notes: notes)

        await #expect(throws: RPCError.self) { try await balances.refresh(account, on: .devnet) }
        #expect(await notes.value == [id: NoteSyncState()])

        #expect(try await balances.refresh(account, on: .devnet) == .lamports(42))
        #expect(await notes.value?[id]?.lamports == 42)
        #expect(try await Self.methods(of: responses).filter { $0 == GetShieldedTransactionsByTags.method }.count == 2)
    }

    /// A cancelled refresh fails with `CancellationError`, while the sync it started finishes and saves the notes.
    @Test
    func `A cancelled refresh fails while the shared sync still saves`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let gate = Suspension()
        let responses = HTTPResponses.privateNotes(
            deposits: [try PrivateBalanceFixtures.deposit(42, to: record.shieldedAccount(for: account.address), leafIndex: 1)],
            gate: gate, heldMethod: GetShieldedTransactionsByTags.method
        )
        let id = PrivateBalances.noteID(of: account, on: .devnet)
        let notes = StoredValue<PrivateBalances.Notes>([id: NoteSyncState()])
        let balances = try Self.balances(responses, keys: StoredValue([account.address.value: record]), notes: notes)

        let refresh = await Self.startRefresh(of: account, in: balances)
        await gate.waitUntilStarted()
        refresh.cancel()
        gate.resume()

        await #expect(throws: CancellationError.self) { try await refresh.value }
        #expect(await notes.value?[id]?.lamports == 42)
        #expect(!(await responses.wasCancelled))
    }

    /// A reset while a sync waits on the indexer leaves no notes or keys once the sync finishes.
    @Test
    func `A reset during a sync leaves no notes`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let gate = Suspension()
        let responses = HTTPResponses.privateNotes(
            deposits: [try PrivateBalanceFixtures.deposit(42, to: record.shieldedAccount(for: account.address), leafIndex: 1)],
            gate: gate, heldMethod: GetShieldedTransactionsByTags.method
        )
        let keys = StoredValue([account.address.value: record])
        let notes = StoredValue<PrivateBalances.Notes>([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
        let balances = try Self.balances(responses, keys: keys, notes: notes)

        let refresh = await Self.startRefresh(of: account, in: balances)
        await gate.waitUntilStarted()
        try await balances.removeAll()
        gate.resume()

        await #expect(throws: CancellationError.self) { try await refresh.value }
        #expect(await notes.value == nil)
        #expect(await keys.value == nil)
    }

    /// Another account's refresh finishes while one account's sync waits on the indexer.
    @Test
    func `Other accounts refresh while one account syncs`() async throws {
        async let derivedSyncing = PrivateBalanceFixtures.account(index: 0)
        async let derivedOther = PrivateBalanceFixtures.account(index: 1)
        let (syncing, other) = try await (derivedSyncing, derivedOther)
        let gate = Suspension()
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered], gate: gate,
                                                   heldMethod: GetShieldedTransactionsByTags.method)
        let keys = StoredValue([syncing.address.value: try await PrivateBalanceFixtures.keys(for: syncing),
                                other.address.value: try await PrivateBalanceFixtures.keys(for: other)])
        let notes = StoredValue<PrivateBalances.Notes>([PrivateBalances.noteID(of: syncing, on: .devnet): NoteSyncState()])
        let balances = try Self.balances(responses, keys: keys, notes: notes)

        let sync = await Self.startRefresh(of: syncing, in: balances)
        await gate.waitUntilStarted()
        let otherStatus = try await balances.refresh(other, on: .devnet)
        gate.resume()

        #expect(otherStatus == .unregistered)
        #expect(try await sync.value == .lamports(0))
    }

    /// Creates private balances around local responses and in-memory storage.
    ///
    /// Storage defaults to `nil` instead of new storage: an actor initializer in a default argument fails the test
    /// module's emit-module job.
    /// - Parameters:
    ///   - responses: The local responses that every network's provider client sends requests to.
    ///   - provider: The selected provider; Helius by default.
    ///   - recovery: The recovery storage; the published fixture recovery by default.
    ///   - keys: Each account's keys; empty storage by default.
    ///   - notes: Each account's notes; empty storage by default.
    /// - Returns: Private balances whose requests never leave the process.
    /// - Throws: A validation error, which doesn't happen.
    private static func balances(
        _ responses: HTTPResponses, provider: ProviderSettings.Provider = .helius,
        recovery: SecurityRecoveryStore? = nil, keys: StoredValue<PrivateBalances.Keys>? = nil,
        notes: StoredValue<PrivateBalances.Notes>? = nil
    ) throws -> PrivateBalances {
        PrivateBalances.inMemory(keys: keys ?? StoredValue(), notes: notes ?? StoredValue(),
                                 recovery: try recovery ?? PrivateBalanceFixtures.recoveryStore(), responses: responses,
                                 provider: provider)
    }

    /// A selected custom RPC, which serves only mainnet.
    /// - Returns: The custom RPC provider.
    /// - Throws: A test prerequisite error, which doesn't happen.
    private static func customRPC() throws -> ProviderSettings.Provider {
        .custom(try #require(URL(string: "https://rpc.example.com")))
    }

    /// Lists the RPC methods of the requests sent so far.
    /// - Parameter responses: The local responses that recorded the requests.
    /// - Returns: Each request's method, in arrival order.
    /// - Throws: A test prerequisite error for a request without a method.
    private static func methods(of responses: HTTPResponses) async throws -> [String] {
        try await responses.requests.map { try $0.rpcMethod }
    }

    /// Starts a refresh that reaches the shared sync before this call returns.
    ///
    /// The task starts on the actor at once, so it joins or starts the account's sync before the caller continues.
    /// - Parameters:
    ///   - account: The account to refresh on devnet.
    ///   - balances: The private balances, whose isolation this call runs in.
    /// - Returns: The refresh's task.
    private static func startRefresh(of account: widgets.Account,
                                     in balances: isolated PrivateBalances) -> Task<PrivateBalanceStatus, any Error> {
        Task.immediate { try await balances.refresh(account, on: .devnet) }
    }
}
