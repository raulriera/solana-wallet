import Foundation
import Portfolio
import Privacy
import Testing
import Transactions
@testable import RPC
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PrivateBalanceStoreTests {
    nonisolated private static let sol = Holding(
        id: .nativeSOL,
        amount: Amount(units: 2_000_000_000, decimals: 9),
        name: "Solana",
        symbol: "SOL",
        imageURL: nil,
        valuation: nil
    )

    nonisolated private static let devnetUSDC = Holding(
        id: .asset("4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU"),
        amount: Amount(units: 5_000_000, decimals: 6),
        name: "USD Coin",
        symbol: "USDC",
        imageURL: nil,
        valuation: nil
    )

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

    @Test(arguments: [
        (PrivateBalanceFixtures.Balance.available, Self.sol, Decimal(2), Decimal(string: "0.001")!),
        (.availableToken, Self.devnetUSDC, 5, 1),
    ])
    func `Moves take the balance they leave`(
        fixture: PrivateBalanceFixtures.Balance,
        holding: Holding,
        publicBalance: Decimal,
        privateBalance: Decimal
    ) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let store = try await PrivateBalanceFixtures.store(holding: fixture, of: account)
        await store.refresh(account, on: .devnet)

        let deposit = store.move(.toPrivate, of: holding, for: account, on: .devnet)
        let withdrawal = store.move(.toPublic, of: holding, for: account, on: .devnet)

        #expect(deposit?.direction == .toPrivate)
        #expect(deposit?.payment.source == .publicBalance)
        #expect(deposit?.payment.token.balance == publicBalance)
        #expect(withdrawal?.direction == .toPublic)
        #expect(withdrawal?.payment.source == .privateBalance)
        #expect(withdrawal?.payment.token.balance == privateBalance)
    }

    @Test(arguments: [
        Holding(
            id: .asset("So11111111111111111111111111111111111111112"),
            amount: Amount(units: 1, decimals: 9),
            name: nil,
            symbol: "wSOL",
            imageURL: nil,
            valuation: nil
        ),
        Holding(
            id: .nativeSOL,
            amount: Amount(units: 1, decimals: 9),
            otherOwner: try? Address("4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"),
            name: nil,
            symbol: "SOL",
            imageURL: nil,
            valuation: nil
        ),
    ])
    func `No move opens for another owner's holding or a token private balances don't hold`(
        holding: Holding
    )
        async throws
    {
        let account = try await PrivateBalanceFixtures.account()
        let store = try await PrivateBalanceFixtures.store(holding: .available, of: account)
        await store.refresh(account, on: .devnet)

        #expect(store.move(.toPrivate, of: holding, for: account, on: .devnet) == nil)
    }

    @Test(arguments: [PrivateBalanceFixtures.Balance.pending, .unregistered])
    func `No withdrawal opens without available SOL`(holding: PrivateBalanceFixtures.Balance) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let store = try await PrivateBalanceFixtures.store(holding: holding, of: account)
        await store.refresh(account, on: .devnet)

        #expect(store.move(.toPublic, of: Self.sol, for: account, on: .devnet) == nil)
        #expect(store.move(.toPrivate, of: Self.sol, for: account, on: .devnet) != nil)
    }

    @Test
    func `No move opens while private balances are off or unread`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let store = try PrivateBalanceStore.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]))
        let unread = store.move(.toPrivate, of: Self.sol, for: account, on: .devnet)
        await store.refresh(account, on: .devnet)

        let off = store.move(.toPrivate, of: Self.sol, for: account, on: .devnet)

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
