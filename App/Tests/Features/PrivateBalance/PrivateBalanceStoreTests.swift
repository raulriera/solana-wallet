import Foundation
import Privacy
import Testing
import Transactions
@testable import RPC
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PrivateBalanceStoreTests {
    @Test
    func `Nothing shows before a window observes the account`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes()
        let store = try PrivateBalanceStore.fixture(responses)

        #expect(store.balance(for: account, on: .devnet) == nil)
        #expect(await responses.requests.isEmpty)
    }

    @Test
    func `Windows on the same account and network share one balance`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let store = try PrivateBalanceStore.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]))
        let first = Task { await store.observe(account, on: .devnet) }
        defer { first.cancel() }
        try await PrivateBalanceFixtures.status(of: account, in: store, becomes: .off(isRegistered: false))
        let balance = store.balance(for: account, on: .devnet)

        await store.refresh(account, on: .devnet)

        #expect(store.balance(for: account, on: .devnet) === balance)
        #expect(store.balance(for: account, on: .mainnet) == nil)
    }

    @Test
    func `A settled private move reads the balance again for every window`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let registry = try PrivateBalanceFixtures.registry(publishing: record.shieldedAccount(for: account.address))
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered, registry])
        let sent = try PendingMove(from: account.id)
        let store = try PrivateBalanceStore.fixture(responses, keys: StoredValue([account.address.value: record]),
                                                    transactions: sent.transactions)
        let first = Task { await store.observe(account, on: .devnet) }
        defer { first.cancel() }
        let second = Task { await store.observe(account, on: .devnet) }
        defer { second.cancel() }
        try await PrivateBalanceFixtures.status(of: account, in: store, becomes: .unregistered)

        #expect(try await sent.settle() == .succeeded)

        try await PrivateBalanceFixtures.status(of: account, in: store, becomes: .balance(available: 0, pending: 0))
    }

    @Test
    func `A new provider reads the observed balances again`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let registry = try PrivateBalanceFixtures.registry(publishing: record.shieldedAccount(for: account.address))
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered, registry])
        let rpcStore = RPCStore.inMemory(selection: .helius, key: "fixture-key")
        await rpcStore.load()
        let store = try PrivateBalanceStore.fixture(responses, keys: StoredValue([account.address.value: record]),
                                                    rpcStore: rpcStore)
        let viewing = Task { await store.observe(account, on: .devnet) }
        defer { viewing.cancel() }
        try await PrivateBalanceFixtures.status(of: account, in: store, becomes: .unregistered)

        try await rpcStore.select(.solana)

        try await PrivateBalanceFixtures.status(of: account, in: store, becomes: .balance(available: 0, pending: 0))
    }

    @Test
    func `Overlapping refreshes share one read`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys = StoredValue([account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered])
        let store = try PrivateBalanceStore.fixture(responses, keys: keys)

        async let first: Void = store.refresh(account, on: .devnet)
        async let second: Void = store.refresh(account, on: .devnet)
        _ = await (first, second)

        #expect(store.balance(for: account, on: .devnet)?.status == .unregistered)
        #expect(await PrivateBalanceFixtures.nonTreeAccountReads(of: responses) == 1)
    }

    @Test
    func `Moves take the SOL of the balance they leave`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let store = try await PrivateBalanceFixtures.store(holding: .available, of: account)
        await store.refresh(account, on: .devnet)

        let deposit = store.move(.toPrivate, publicLamports: 2_000_000_000, for: account, on: .devnet)
        let withdrawal = store.move(.toPublic, publicLamports: 2_000_000_000, for: account, on: .devnet)

        #expect(deposit?.direction == .toPrivate)
        #expect(deposit?.payment.source == .publicBalance)
        #expect(deposit?.payment.token.balance == 2)
        #expect(withdrawal?.direction == .toPublic)
        #expect(withdrawal?.payment.source == .privateBalance)
        #expect(withdrawal?.payment.token.balance == Decimal(string: "0.001"))
    }

    @Test(arguments: [PrivateBalanceFixtures.Balance.pending, .unregistered])
    func `No withdrawal opens without available SOL`(holding: PrivateBalanceFixtures.Balance) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let store = try await PrivateBalanceFixtures.store(holding: holding, of: account)
        await store.refresh(account, on: .devnet)

        #expect(store.move(.toPublic, publicLamports: 2_000_000_000, for: account, on: .devnet) == nil)
        #expect(store.move(.toPrivate, publicLamports: 2_000_000_000, for: account, on: .devnet) != nil)
    }

    @Test
    func `No move opens while private balances are off or unread`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let store = try PrivateBalanceStore.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]))
        let unread = store.move(.toPrivate, publicLamports: 2_000_000_000, for: account, on: .devnet)
        await store.refresh(account, on: .devnet)

        let off = store.move(.toPrivate, publicLamports: 2_000_000_000, for: account, on: .devnet)

        #expect(unread == nil)
        #expect(off == nil)
    }

    @Test
    func `Erasing drops the read that's running`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let gate = Suspension()
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered], gate: gate,
                                                   heldMethod: GetMultipleAccounts.method)
        let store = try PrivateBalanceStore.fixture(responses)
        let running = Task { await store.refresh(account, on: .devnet) }
        await gate.waitUntilStarted()
        let erased = try #require(store.balance(for: account, on: .devnet))

        try await store.erase()
        gate.resume()
        await running.value

        #expect(erased.status == nil)
    }

    @Test
    func `Erasing forgets every balance`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let store = try PrivateBalanceStore.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]))
        await store.refresh(account, on: .devnet)
        let erased = try #require(store.balance(for: account, on: .devnet))

        try await store.erase()

        #expect(store.balance(for: account, on: .devnet) == nil)
        #expect(erased.status == nil)
    }
}
