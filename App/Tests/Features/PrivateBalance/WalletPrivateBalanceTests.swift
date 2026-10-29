import Foundation
import Observation
import Privacy
import Storage
import Testing
import Transactions
import Wallet
@testable import RPC
@testable import widgets

/// Checks one account's shared private balance: its reads, polls, and follow-ups, through real private balances and
/// local indexer fixtures.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WalletPrivateBalanceTests {
    /// A read shows why the account has no balance yet.
    @Test
    func `A read shows the account's status`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let store = try PrivateBalanceStore.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]))

        let balance = try await PrivateBalanceFixtures.read(account, in: store)

        #expect(balance.status == .off(isRegistered: false))
    }

    /// An account at a path without private-balance keys shows nothing and reads nothing.
    @Test
    func `An account at another path shows nothing`() async throws {
        let responses = HTTPResponses.privateNotes()
        let store = try PrivateBalanceStore.fixture(responses)

        let balance = try await PrivateBalanceFixtures.read(try await Self.otherPathAccount(), in: store)

        #expect(balance.status == nil)
        #expect(await responses.requests.isEmpty)
    }

    /// A read that fails keeps the status that the last read found, marked outdated.
    @Test
    func `A failed read keeps the last status`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys = StoredValue<PrivateBalances.Keys>()
        let responses = HTTPResponses.privateNotes(error: .http(statusCode: 429, retryAfter: nil))
        let store = try PrivateBalanceStore.fixture(responses, keys: keys)
        let balance = try await PrivateBalanceFixtures.read(account, in: store)
        let wasOutdated = balance.isOutdated
        try await keys.save([account.address.value: PrivateBalanceFixtures.keys(for: account)])

        await balance.refresh()

        #expect(!wasOutdated)
        #expect(balance.status == .off(isRegistered: false))
        #expect(balance.isOutdated)
    }

    /// A first read that fails shows the balance that the saved notes hold, marked outdated.
    @Test
    func `A failed first read shows the saved balance as outdated`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let failing = HTTPResponses.privateNotes(error: .http(statusCode: 500, retryAfter: nil))
        let store = try await PrivateBalanceFixtures.pendingDeposit(of: account, responses: failing).store

        let balance = try await PrivateBalanceFixtures.read(account, in: store)

        #expect(balance.status == .balance(available: 0, pending: 1_000_000))
        #expect(balance.isOutdated)
    }

    /// A read that finds the account registered with other keys shows nothing, without marking the balance outdated.
    @Test
    func `Keys that another app registered aren't an outdated balance`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        let other = try PrivateBalanceFixtures.otherKeys(for: account.address)
        let responses = HTTPResponses.privateNotes(registry: [try PrivateBalanceFixtures.registry(publishing: other)])
        let store = try PrivateBalanceStore.fixture(responses, keys: keys)

        let balance = try await PrivateBalanceFixtures.read(account, in: store)

        #expect(balance.status == nil)
        #expect(!balance.isOutdated)
    }

    /// A first read that fails without saved notes shows no status, and polls read again until a read succeeds.
    @Test
    func `A failed first read without saved notes polls until a read succeeds`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let providers = ProviderStore.inMemory(selection: .helius, key: "failing-key")
        let balance = try await Self.balance(
            of: account, providers: providers,
            responses: HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]),
            otherResponses: HTTPResponses.privateNotes(error: .http(statusCode: 500, retryAfter: nil))
        )
        await balance.refresh()
        let failedStatus = balance.status
        let wasOutdated = balance.isOutdated

        try await providers.save(key: "fixture-key")
        await balance.poll()

        #expect(failedStatus == nil)
        #expect(wasOutdated)
        #expect(balance.status == .unregistered)
        #expect(!balance.isOutdated)
    }

    /// A registered account with SOL in its private balance has a balance; one without SOL doesn't.
    @Test
    func `Only private SOL counts as a balance`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let funded = try await PrivateBalanceFixtures.read(account, in: try await PrivateBalanceFixtures.store(holding: .available,
                                                                                                             of: account))
        let unfunded = try await PrivateBalanceFixtures.read(account,
                                                             in: try await PrivateBalanceFixtures.store(holding: .unregistered,
                                                                                                        of: account))

        #expect(funded.status == .balance(available: 1_000_000, pending: 0))
        #expect(funded.hasBalance)
        #expect(funded.availableLamports == 1_000_000)
        #expect(unfunded.status == .unregistered)
        #expect(!unfunded.hasBalance)
        #expect(unfunded.availableLamports == nil)
    }

    /// A settled private deposit or withdrawal becomes the account's last settled move, which reads the balance again.
    /// - Parameter kind: The private move.
    @Test(arguments: [TransactionRecord.Kind.privateDeposit(lamports: 1_000_000),
                      .privateWithdrawal(lamports: 1_000_000)])
    func `A settled private move becomes the last settled move`(kind: TransactionRecord.Kind) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let sent = try PendingMove(kind, from: account.id)
        let store = try await PrivateBalanceFixtures.store(holding: .pending, of: account, transactions: sent.transactions)
        let balance = try await PrivateBalanceFixtures.read(account, in: store)
        #expect(balance.lastSettledMove == nil)

        #expect(try await sent.settle() == .succeeded)

        #expect(balance.lastSettledMove?.id == sent.record.id)
    }

    /// A payment never changes the private balance, so a settled one isn't a settled move and starts no follow-up on
    /// pending SOL.
    @Test
    func `A settled payment is no settled move and starts no follow-up`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let sent = try PendingPayment(from: account.id)
        let store = try await PrivateBalanceFixtures.store(holding: .pending, of: account, transactions: sent.transactions)
        let balance = try await PrivateBalanceFixtures.read(account, in: store)

        #expect(try await sent.settle() == .succeeded)
        await balance.refresh()

        #expect(balance.lastSettledMove == nil)
        #expect(!balance.isFollowingUp)
    }

    /// A read after settling reads the account's records, and the last settled move is the deposit or withdrawal that
    /// settled last, whatever order the moves were sent in; payments and pending moves don't count.
    @Test
    func `The last settled move is the private move that settled last`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let key = TransactionRecord.Key(account: account.id, network: .devnet)
        // Newest first, as the store keeps them.
        let records: [TransactionRecord] = [
            .fixture(.privateDeposit(lamports: 1), signature: "pending deposit", account: account.id, created: 40),
            .fixture(.payment(recipient: account.address, mint: nil, units: 1), signature: "payment",
                     account: account.id, status: .succeeded, created: 30, settled: 35),
            .fixture(.privateWithdrawal(lamports: 1), signature: "withdrawal", account: account.id,
                     status: .failed, created: 20, settled: 25),
            .fixture(.privateDeposit(lamports: 1), signature: "deposit", account: account.id, status: .succeeded,
                     created: 10, settled: 28),
        ]
        let store = try await PrivateBalanceFixtures.store(holding: .available, of: account,
                                                           transactions: .inMemory([key: StoredValue(records)]))
        let balance = try await PrivateBalanceFixtures.read(account, in: store)

        await balance.readAfterSettling()

        #expect(balance.lastSettledMove?.id == "deposit")
        #expect(balance.status == .balance(available: 1_000_000, pending: 0))
    }

    /// A read after settling never shares a read that's running, which may have started before the move settled.
    @Test
    func `A read after settling waits for the running read, then reads again`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let registry = try PrivateBalanceFixtures.registry(publishing: record.shieldedAccount(for: account.address))
        let gate = Suspension()
        // The running read finds the account unregistered; the read after settling finds it registered.
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered, registry],
                                                   gate: gate, heldMethod: GetMultipleAccounts.method)
        let transactions = TransactionStore.unused
        let store = try PrivateBalanceStore.fixture(responses, keys: StoredValue([account.address.value: record]),
                                                    transactions: transactions)
        let running = Task { await store.refresh(account, on: .devnet) }
        await gate.waitUntilStarted()
        let balance = try #require(store.balance(for: account, on: .devnet))

        let settling = Task { await balance.readAfterSettling() }
        // Once the account's records are read, the read after settling waits on the running read.
        let key = TransactionRecord.Key(account: account.id, network: .devnet)
        for await phase in Observations({ transactions.phase(for: key) }) where phase == .loaded { break }
        gate.resume()
        await running.value
        await settling.value

        #expect(await PrivateBalanceFixtures.registryReads(of: responses) == 2)
        #expect(balance.status == .balance(available: 0, pending: 0))
    }

    /// The first read after one of the account's private moves settles follows up quickly on pending SOL, with at most
    /// ten quick reads; pending SOL before the move settled starts none.
    @Test
    func `A read after a settled private move with pending SOL starts a follow-up`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let sent = try PendingMove(from: account.id)
        let store = try await PrivateBalanceFixtures.store(holding: .pending, of: account, transactions: sent.transactions)
        let balance = try await PrivateBalanceFixtures.read(account, in: store)
        #expect(!balance.isFollowingUp)

        try #require(await sent.settle() == .succeeded)
        await balance.refresh()

        #expect(balance.followUpReadsLeft == WalletPrivateBalance.followUpReads)
    }

    /// A read after one of the account's private moves settles starts no follow-up when nothing is pending.
    @Test
    func `A read after a settled private move without pending SOL starts no follow-up`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let sent = try PendingMove(from: account.id)
        let store = try await PrivateBalanceFixtures.store(holding: .available, of: account,
                                                           transactions: sent.transactions)
        let balance = try await PrivateBalanceFixtures.read(account, in: store)

        try #require(await sent.settle() == .succeeded)
        await balance.refresh()

        #expect(!balance.isFollowingUp)
    }

    /// Each follow-up poll uses one quick read, and a read that finds nothing pending ends the follow-up.
    @Test
    func `A follow-up ends once nothing is pending`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let sent = try PendingMove(from: account.id)
        let (store, notes) = try await PrivateBalanceFixtures.pendingDeposit(of: account,
                                                                             transactions: sent.transactions)
        let balance = try await PrivateBalanceFixtures.read(account, in: store)
        try #require(await sent.settle() == .succeeded)
        await balance.refresh()
        try #require(balance.followUpReadsLeft == WalletPrivateBalance.followUpReads)

        await balance.poll()
        #expect(balance.followUpReadsLeft == WalletPrivateBalance.followUpReads - 1)
        // The indexer reports the deposit, so nothing is pending.
        try await notes.save([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
        await balance.poll()

        #expect(balance.status == .balance(available: 0, pending: 0))
        #expect(!balance.isFollowingUp)
    }

    /// A poll reads the balance again while private balances are on.
    @Test
    func `Polls read while private balances are on`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered])
        let store = try PrivateBalanceStore.fixture(responses, keys: keys)
        let balance = try await PrivateBalanceFixtures.read(account, in: store)

        await balance.poll()

        #expect(await PrivateBalanceFixtures.registryReads(of: responses) == 2)
    }

    /// While private balances are off, a poll reads nothing.
    @Test
    func `Polls read nothing while private balances are off`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered])
        let store = try PrivateBalanceStore.fixture(responses)
        let balance = try await PrivateBalanceFixtures.read(account, in: store)
        let readRequests = await responses.requests.count

        await balance.poll()

        #expect(await responses.requests.count == readRequests)
    }

    /// A rejected key pauses polling, so polls send nothing even once a new key is saved, until a refresh succeeds.
    @Test
    func `Paused polling waits for a refresh that succeeds`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered])
        let providers = ProviderStore.inMemory(selection: .helius, key: "fixture-key")
        let balance = try await Self.balance(
            of: account, providers: providers, responses: responses,
            otherResponses: HTTPResponses.privateNotes(error: .http(statusCode: 401, retryAfter: nil))
        )
        await balance.refresh()

        try await providers.save(key: "rejected-key")
        await balance.poll()
        let isPaused = balance.isPollingPaused
        try await providers.save(key: "fixture-key")
        let pausedRequests = await responses.requests.count
        await balance.poll()
        let pausedPollRequests = await responses.requests.count - pausedRequests
        await balance.refresh()

        #expect(isPaused)
        #expect(pausedPollRequests == 0)
        #expect(!balance.isPollingPaused)
        #expect(balance.status == .unregistered)
    }

    /// A failure that can clear by itself, such as a server error, keeps polling.
    @Test
    func `A failure that can clear by itself keeps polling`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        let store = try PrivateBalanceStore.fixture(HTTPResponses.privateNotes(error: .http(statusCode: 503, retryAfter: nil)),
                                                    keys: keys)

        let balance = try await PrivateBalanceFixtures.read(account, in: store)

        #expect(!balance.isPollingPaused)
    }

    /// A rate limit pauses polling.
    @Test
    func `A rate limit pauses polling`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        let store = try PrivateBalanceStore.fixture(HTTPResponses.privateNotes(error: .http(statusCode: 429, retryAfter: nil)),
                                                    keys: keys)

        let balance = try await PrivateBalanceFixtures.read(account, in: store)

        #expect(balance.isPollingPaused)
    }

    /// One account's private balance on devnet, with its keys saved and no notes, whose responses follow the saved
    /// Helius key.
    /// - Parameters:
    ///   - account: The account.
    ///   - providers: The provider settings whose saved key picks the responses.
    ///   - responses: The responses for the key `fixture-key`.
    ///   - otherResponses: The responses for any other key.
    /// - Returns: The balance.
    /// - Throws: A derivation or test prerequisite error.
    private static func balance(of account: widgets.Account, providers: ProviderStore, responses: HTTPResponses,
                                otherResponses: HTTPResponses) async throws -> WalletPrivateBalance {
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let balances = PrivateBalances(recovery: try PrivateBalanceFixtures.recoveryStore(), wallet: Wallet(),
                                       keys: StoredValue([account.address.value: record]), notes: StoredValue(),
                                       codes: StoredValue()) { network in
            ProviderClient(network: network, providers: providers) { endpoint, network in
                (endpoint == .helius(key: "fixture-key") ? responses : otherResponses).client(for: endpoint, on: network)
            }
        }
        return WalletPrivateBalance(account: account, network: .devnet, balances: balances, transactions: .unused,
                                    pollInterval: .seconds(30), followUpInterval: .seconds(3))
    }

    /// The fixture account's address at a path without private-balance keys.
    /// - Returns: The account.
    /// - Throws: A derivation or test prerequisite error.
    private static func otherPathAccount() async throws -> widgets.Account {
        let fixture = try await PrivateBalanceFixtures.account()
        return widgets.Account(id: UUID(), recoveryID: PrivateBalanceFixtures.recoveryID, address: fixture.address,
                               path: try DerivationPath("m/44'/501'/0'"))
    }
}
