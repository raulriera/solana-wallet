import Foundation
import Observation
import Portfolio
import Privacy
import Storage
import Testing
import Transactions
import Wallet
@testable import RPC
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WalletPrivateBalanceTests {
    @Test
    func `An account at another path shows nothing`() async throws {
        let responses = HTTPResponses.privateNotes()
        let store = try PrivateBalanceStore.fixture(responses)

        let balance = try await PrivateBalanceFixtures.read(try await Self.otherPathAccount(), in: store)

        #expect(balance.status == nil)
        #expect(await responses.requests.isEmpty)
    }

    @Test
    func `A failed read keeps the last status`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys = StoredValue<PrivateBalances.Keys>()
        let responses = HTTPResponses.privateNotes(error: .http(statusCode: 429, retryAfter: nil))
        let store = try PrivateBalanceStore.fixture(responses, keys: keys)
        let balance = try await PrivateBalanceFixtures.read(account, in: store)
        let wasStale = balance.isStale
        try await keys.save([account.address.value: PrivateBalanceFixtures.keys(for: account)])

        await balance.refresh()

        #expect(!wasStale)
        #expect(balance.status == .off(isRegistered: false))
        #expect(balance.isStale)
    }

    @Test
    func `A failed first read shows the saved balance as stale`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let failing = HTTPResponses.privateNotes(error: .http(statusCode: 500, retryAfter: nil))
        let store = try await PrivateBalanceFixtures.pendingDeposit(of: account, responses: failing).store

        let balance = try await PrivateBalanceFixtures.read(account, in: store)

        #expect(balance.status == .balance(available: 0, pending: 1_000_000, of: .nativeSOL))
        #expect(balance.isStale)
    }

    @Test
    func `Keys that another app registered aren't a stale balance`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        let other = try PrivateBalanceFixtures.otherKeys(for: account.address)
        let responses = HTTPResponses.privateNotes(registry: [try PrivateBalanceFixtures.registry(publishing: other)])
        let store = try PrivateBalanceStore.fixture(responses, keys: keys)

        let balance = try await PrivateBalanceFixtures.read(account, in: store)

        #expect(balance.status == nil)
        #expect(!balance.isStale)
    }

    @Test
    func `A failed first read without saved notes polls until a read succeeds`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let rpcStore = RPCStore.inMemory(selection: .helius, key: "failing-key")
        let balance = try await Self.balance(
            of: account, rpcStore: rpcStore,
            responses: HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]),
            otherResponses: HTTPResponses.privateNotes(error: .http(statusCode: 500, retryAfter: nil))
        )
        await balance.refresh()
        let failedStatus = balance.status
        let wasStale = balance.isStale

        try await rpcStore.save(key: "fixture-key")
        await balance.poll()

        #expect(failedStatus == nil)
        #expect(wasStale)
        #expect(balance.status == .unregistered)
        #expect(!balance.isStale)
    }

    @Test(arguments: [
        (PrivateBalanceFixtures.Balance.available, PrivateAsset.nativeSOL),
        (.availableToken, .token(.devnetUSDC)),
        (.unregistered, nil),
    ] as [(PrivateBalanceFixtures.Balance, PrivateAsset?)])
    func `Only an asset with a private amount is available and held`(
        fixture: PrivateBalanceFixtures.Balance,
        asset: PrivateAsset?
    ) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let store = try await PrivateBalanceFixtures.store(holding: fixture, of: account)

        let balance = try await PrivateBalanceFixtures.read(account, in: store)

        #expect(balance.privateAssets == Set(asset.map { [$0.asset] } ?? []))
        for other in PrivateAsset.allCases {
            #expect(balance.available(of: other) == (other == asset ? UInt64(1_000_000) : nil))
        }
    }

    @Test
    func `A settled private move becomes the last settled move`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let sent = try PendingMove(from: account.id)
        let store = try await PrivateBalanceFixtures.store(holding: .pending, of: account, transactions: sent.transactions)
        let balance = try await PrivateBalanceFixtures.read(account, in: store)
        #expect(balance.lastSettledMove == nil)

        #expect(try await sent.settle() == .succeeded)

        #expect(balance.lastSettledMove?.id == sent.record.id)
    }

    @Test
    func `The last settled move is the private move that settled last`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let key = TransactionRecord.Key(account: account.id, network: .devnet)
        let sockets = SocketSequence()
        let coordinator = try LocalTransactions(fixture: SigningFixture(), statuses: [.status(.finalized)],
                                                sockets: sockets).coordinator
        let transactions = TransactionStore.inMemory(StoredValue([
            .fixture(.privateDeposit, signature: "pending deposit", account: account.id),
            .fixture(.privateWithdrawal, signature: "withdrawal", account: account.id),
            .fixture(.payment, signature: "payment", account: account.id),
            .fixture(.privateDeposit, signature: "deposit", account: account.id),
        ])) { _ in coordinator }
        let store = try await PrivateBalanceFixtures.store(holding: .available, of: account, transactions: transactions)
        let balance = try await PrivateBalanceFixtures.read(account, in: store)
        for signature in ["withdrawal", "deposit", "payment"] {
            _ = try await transactions.watch(signature, for: key)
        }
        await sockets.waitUntilClosed()

        await balance.readAfterSettling()

        #expect(balance.lastSettledMove?.id == "deposit")
        #expect(balance.status == .balance(available: 1_000_000, pending: 0, of: .nativeSOL))
    }

    @Test
    func `A read after settling waits for the running read, then reads again`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let registry = try PrivateBalanceFixtures.registry(publishing: record.shieldedAccount(for: account.address))
        let gate = Suspension()
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered, registry],
                                                   gate: gate, heldMethod: GetMultipleAccounts.method)
        let transactions = TransactionStore.unused
        let store = try PrivateBalanceStore.fixture(responses, keys: StoredValue([account.address.value: record]),
                                                    transactions: transactions)
        let running = Task { await store.refresh(account, on: .devnet) }
        await gate.waitUntilStarted()
        let balance = try #require(store.balance(for: account, on: .devnet))

        let settling = Task { await balance.readAfterSettling() }
        await transactions.load()
        gate.resume()
        await running.value
        await settling.value

        #expect(await PrivateBalanceFixtures.nonTreeAccountReads(of: responses) == 2)
        #expect(balance.status == .balance(available: 0, pending: 0, of: .nativeSOL))
    }

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

    @Test
    func `A follow-up ends once nothing is pending`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let sent = try PendingMove(from: account.id)
        let (store, notes) = try await PrivateBalanceFixtures.pendingDeposit(of: account,
                                                                             transactions: sent.transactions)
        let balance = try await PrivateBalanceFixtures.read(account, in: store)
        try #require(await sent.settle() == .succeeded)
        await balance.refresh()
        try #require(balance.followUpReadsLeft == 10)

        await balance.poll()
        #expect(balance.followUpReadsLeft == 9)
        try await notes.save([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
        await balance.poll()

        #expect(balance.status == .balance(available: 0, pending: 0, of: .nativeSOL))
        #expect(!balance.isFollowingUp)
    }

    @Test
    func `An observed balance is read again after each interval`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let registry = try PrivateBalanceFixtures.registry(publishing: record.shieldedAccount(for: account.address))
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered, registry])
        let clock = ManualClock()
        var waits = clock.waits.makeAsyncIterator()
        let store = try PrivateBalanceStore.fixture(responses, keys: StoredValue([account.address.value: record]),
                                                    clock: clock)
        let viewing = Task { await store.observe(account, on: .devnet) }
        defer { viewing.cancel() }

        #expect(try await clock.advanceToNextWait(&waits) == .seconds(30))

        try await PrivateBalanceFixtures.status(of: account, in: store, becomes: .balance(available: 0, pending: 0, of: .nativeSOL))
    }

    @Test
    func `Pending SOL after a settled private move is read again quickly`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let sent = try PendingMove(from: account.id)
        let clock = ManualClock()
        var waits = clock.waits.makeAsyncIterator()
        let (store, notes) = try await PrivateBalanceFixtures.pendingDeposit(of: account,
                                                                             transactions: sent.transactions,
                                                                             clock: clock)
        let viewing = Task { await store.observe(account, on: .devnet) }
        defer { viewing.cancel() }
        try await PrivateBalanceFixtures.status(of: account, in: store,
                                                becomes: .balance(available: 0, pending: 1_000_000, of: .nativeSOL))
        let balance = try #require(store.balance(for: account, on: .devnet))
        #expect(!balance.isFollowingUp)
        #expect(try await clock.durationToNextWait(&waits) == .seconds(30))

        #expect(try await sent.settle() == .succeeded)

        for await isFollowingUp in Observations({ balance.isFollowingUp }) where isFollowingUp { break }
        try await notes.save([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
        #expect(try await clock.advanceToNextWait(&waits) == .seconds(3))
        for await status in Observations({ balance.status }) where status == .balance(available: 0, pending: 0, of: .nativeSOL) { break }
        #expect(!balance.isFollowingUp)
    }

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

    @Test
    func `Paused polling waits for a refresh that succeeds`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered])
        let rpcStore = RPCStore.inMemory(selection: .helius, key: "fixture-key")
        let balance = try await Self.balance(
            of: account, rpcStore: rpcStore, responses: responses,
            otherResponses: HTTPResponses.privateNotes(error: .http(statusCode: 401, retryAfter: nil))
        )
        await balance.refresh()

        try await rpcStore.save(key: "rejected-key")
        await balance.poll()
        let isPaused = balance.isPollingPaused
        try await rpcStore.save(key: "fixture-key")
        let pausedRequests = await responses.requests.count
        await balance.poll()
        let pausedPollRequests = await responses.requests.count - pausedRequests
        await balance.refresh()

        #expect(isPaused)
        #expect(pausedPollRequests == 0)
        #expect(!balance.isPollingPaused)
        #expect(balance.status == .unregistered)
    }

    @Test(arguments: [(503, false), (429, true)])
    func `A rate limit pauses polling while a failure that can clear by itself keeps polling`(
        status: Int,
        isPaused: Bool
    ) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        let responses = HTTPResponses.privateNotes(error: .http(statusCode: status, retryAfter: nil))
        let store = try PrivateBalanceStore.fixture(responses, keys: keys)

        let balance = try await PrivateBalanceFixtures.read(account, in: store)

        #expect(balance.isPollingPaused == isPaused)
    }

    private static func balance(of account: widgets.Account, rpcStore: RPCStore, responses: HTTPResponses,
                                otherResponses: HTTPResponses) async throws -> WalletPrivateBalance {
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let balances = PrivateBalances(recovery: try PrivateBalanceFixtures.recoveryStore(), wallet: Wallet(),
                                       keys: StoredValue([account.address.value: record]), notes: StoredValue(),
                                       codes: StoredValue()) { network in
            SelectedRPCProvider(network: network, rpcStore: rpcStore) { endpoint, network in
                (endpoint == .helius(key: "fixture-key") ? responses : otherResponses).client(for: endpoint, on: network)
            }
        }
        return WalletPrivateBalance(account: account, network: .devnet, balances: balances, transactions: .unused,
                                    clock: ManualClock())
    }

    private static func otherPathAccount() async throws -> widgets.Account {
        let fixture = try await PrivateBalanceFixtures.account()
        return widgets.Account(id: UUID(), recoveryID: PrivateBalanceFixtures.recoveryID, address: fixture.address,
                               path: try DerivationPath("m/44'/501'/0'"))
    }
}
