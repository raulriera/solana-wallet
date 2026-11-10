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
    func `A read shows the account's status`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let store = try PrivateBalanceStore.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]))

        let balance = try await PrivateBalanceFixtures.read(account, in: store)

        #expect(balance.status == .off(isRegistered: false))
    }

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

        #expect(balance.status == .balance(available: 0, pending: 1_000_000))
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

    @Test
    func `Only an asset with a private amount is held`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let funded = try await PrivateBalanceFixtures.read(account, in: try await PrivateBalanceFixtures.store(holding: .available,
                                                                                                             of: account))
        let unfunded = try await PrivateBalanceFixtures.read(account,
                                                             in: try await PrivateBalanceFixtures.store(holding: .unregistered,
                                                                                                        of: account))

        #expect(funded.status == .balance(available: 1_000_000, pending: 0))
        #expect(funded.privateHoldings == [.nativeSOL])
        #expect(funded.available(of: .sol) == 1_000_000)
        #expect(unfunded.status == .unregistered)
        #expect(unfunded.privateHoldings.isEmpty)
        #expect(unfunded.available(of: .sol) == nil)
    }

    @Test
    func `Private tokens are available and held in their token only`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let balance = try await PrivateBalanceFixtures.read(account, in: try await PrivateBalanceFixtures.store(
            holding: .availableToken, of: account))

        #expect(balance.available(of: .token(.devnetUSDC)) == 1_000_000)
        #expect(balance.available(of: .sol) == nil)
        #expect(balance.privateHoldings == [.asset("4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU")])
    }

    @Test(arguments: [TransactionRecord.Kind.privateDeposit,
                      .privateWithdrawal])
    func `A settled private move becomes the last settled move`(kind: TransactionRecord.Kind) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let sent = try PendingMove(kind, from: account.id)
        let store = try await PrivateBalanceFixtures.store(holding: .pending, of: account, transactions: sent.transactions)
        let balance = try await PrivateBalanceFixtures.read(account, in: store)
        #expect(balance.lastSettledMove == nil)

        #expect(try await sent.settle() == .succeeded)

        #expect(balance.lastSettledMove?.id == sent.record.id)
    }

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

    @Test
    func `The last settled move is the private move that settled last`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let key = TransactionRecord.Key(account: account.id, network: .devnet)
        let records: [TransactionRecord] = [
            .fixture(.privateDeposit, signature: "pending deposit", account: account.id, created: 40),
            .fixture(.payment(recipient: account.address, mint: nil, units: 1), signature: "payment",
                     account: account.id, status: .succeeded, created: 30, settled: 35),
            .fixture(.privateWithdrawal, signature: "withdrawal", account: account.id,
                     status: .failed, created: 20, settled: 25),
            .fixture(.privateDeposit, signature: "deposit", account: account.id, status: .succeeded,
                     created: 10, settled: 28),
        ]
        let store = try await PrivateBalanceFixtures.store(holding: .available, of: account,
                                                           transactions: .inMemory([key: StoredValue(records)]))
        let balance = try await PrivateBalanceFixtures.read(account, in: store)

        await balance.readAfterSettling()

        #expect(balance.lastSettledMove?.id == "deposit")
        #expect(balance.status == .balance(available: 1_000_000, pending: 0))
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
        let key = TransactionRecord.Key(account: account.id, network: .devnet)
        for await phase in Observations({ transactions.phase(for: key) }) where phase == .loaded { break }
        gate.resume()
        await running.value
        await settling.value

        #expect(await PrivateBalanceFixtures.nonTreeAccountReads(of: responses) == 2)
        #expect(balance.status == .balance(available: 0, pending: 0))
    }

    @Test
    func `A read after a settled private move with pending SOL starts a follow-up`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let sent = try PendingMove(from: account.id)
        let store = try await PrivateBalanceFixtures.store(holding: .pending, of: account, transactions: sent.transactions)
        let balance = try await PrivateBalanceFixtures.read(account, in: store)
        #expect(!balance.isFollowingUp)

        try #require(await sent.settle() == .succeeded)
        await balance.refresh()

        #expect(balance.followUpReadsLeft == 10)
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

        #expect(balance.status == .balance(available: 0, pending: 0))
        #expect(!balance.isFollowingUp)
    }

    @Test
    func `Polls read while private balances are on`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered])
        let store = try PrivateBalanceStore.fixture(responses, keys: keys)
        let balance = try await PrivateBalanceFixtures.read(account, in: store)

        await balance.poll()

        #expect(await PrivateBalanceFixtures.nonTreeAccountReads(of: responses) == 2)
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

    @Test
    func `A failure that can clear by itself keeps polling`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        let store = try PrivateBalanceStore.fixture(HTTPResponses.privateNotes(error: .http(statusCode: 503, retryAfter: nil)),
                                                    keys: keys)

        let balance = try await PrivateBalanceFixtures.read(account, in: store)

        #expect(!balance.isPollingPaused)
    }

    @Test
    func `A rate limit pauses polling`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        let store = try PrivateBalanceStore.fixture(HTTPResponses.privateNotes(error: .http(statusCode: 429, retryAfter: nil)),
                                                    keys: keys)

        let balance = try await PrivateBalanceFixtures.read(account, in: store)

        #expect(balance.isPollingPaused)
    }

    private static func balance(of account: widgets.Account, rpcStore: RPCStore, responses: HTTPResponses,
                                otherResponses: HTTPResponses) async throws -> WalletPrivateBalance {
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let balances = PrivateBalances(recovery: try PrivateBalanceFixtures.recoveryStore(), wallet: Wallet(),
                                       keys: StoredValue([account.address.value: record]), notes: StoredValue(),
                                       codes: StoredValue()) { network in
            SelectedRPCProvider(network: network, rpcStore: rpcStore,
                                rings: StubProver.zolana(on: network, transport: responses)) { endpoint, network in
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
