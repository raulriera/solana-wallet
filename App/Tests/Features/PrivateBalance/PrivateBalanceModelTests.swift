import Foundation
import Privacy
import RPC
import Testing
import Transactions
@testable import widgets

/// Checks a Portfolio tab's private-balance workflows, turning private balances on and opening moves, through real
/// private balances and local indexer fixtures.
@MainActor
struct PrivateBalanceModelTests {
    /// Opening a move keeps the move that the shared store creates for the account on the network.
    @Test
    func `Opening keeps the store's move`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let store = try await PrivateBalanceFixtures.store(holding: .available, of: account)
        let model = PrivateBalanceModel()
        await store.refresh(account, on: .devnet)

        model.open(.toPublic, publicLamports: 2_000_000_000, in: store, for: account, on: .devnet)

        let move = try #require(model.move)
        #expect(move.direction == .toPublic)
        #expect(move.payment.token.balance == Decimal(string: "0.001"))
        #expect(model.error == nil)
    }

    /// A move that's open stays until it closes; opening another replaces nothing.
    @Test
    func `A second move keeps the open one`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let store = try await PrivateBalanceFixtures.store(holding: .available, of: account)
        let model = PrivateBalanceModel()
        await store.refresh(account, on: .devnet)
        model.open(.toPrivate, publicLamports: 2_000_000_000, in: store, for: account, on: .devnet)
        let first = try #require(model.move)

        model.open(.toPublic, publicLamports: 2_000_000_000, in: store, for: account, on: .devnet)

        #expect(model.move?.id == first.id)
        #expect(model.move?.direction == .toPrivate)
    }

    /// Turning on keeps the account's keys, then shows its balance in the shared store and reports that it's on.
    @Test
    func `Turning on keeps the keys and shows the balance`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let keys = StoredValue<PrivateBalances.Keys>()
        let store = try PrivateBalanceStore.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]),
                                                    keys: keys)
        let model = PrivateBalanceModel()
        await store.refresh(account, on: .devnet)

        model.turnOn()
        #expect(model.isTurningOn)
        await model.run(model.attempt, in: store, for: account, on: .devnet)

        #expect(store.balance(for: account, on: .devnet)?.status == .unregistered)
        #expect(model.isTurnedOn)
        #expect(!model.isTurningOn)
        #expect(model.error == nil)
        #expect(await keys.value == [account.address.value: try await PrivateBalanceFixtures.keys(for: account)])
    }

    /// A new attempt starts as not turned on, so each attempt that succeeds announces itself again.
    @Test
    func `Each attempt that succeeds turns on again`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let store = try PrivateBalanceStore.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]))
        let model = PrivateBalanceModel()
        model.turnOn()
        await model.run(model.attempt, in: store, for: account, on: .devnet)
        try #require(model.isTurnedOn)

        model.turnOn()

        #expect(!model.isTurnedOn)
        await model.run(model.attempt, in: store, for: account, on: .devnet)
        #expect(model.isTurnedOn)
    }

    /// Keys that another app registered for the account fail turning on with that error, and private balances stay
    /// off.
    @Test
    func `Turning on an account registered with other keys fails`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let other = try PrivateBalanceFixtures.otherKeys(for: account.address)
        let store = try PrivateBalanceStore.fixture(HTTPResponses.privateNotes(registry: [try PrivateBalanceFixtures.registry(publishing: other)]))
        let model = PrivateBalanceModel()
        await store.refresh(account, on: .devnet)

        model.turnOn()
        await model.run(model.attempt, in: store, for: account, on: .devnet)

        #expect(model.error == .registeredWithOtherKeys)
        #expect(store.balance(for: account, on: .devnet)?.status == .off(isRegistered: true))
        #expect(!model.isTurnedOn)
        #expect(!model.isTurningOn)
    }

    /// Dismissing authentication turns nothing on and shows no error.
    @Test
    func `Cancelled authentication shows no error`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let store = try PrivateBalanceStore.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]),
                                                    recovery: SecurityRecoveryStore(readError: CancellationError()))
        let model = PrivateBalanceModel()
        await store.refresh(account, on: .devnet)

        model.turnOn()
        await model.run(model.attempt, in: store, for: account, on: .devnet)

        #expect(model.error == nil)
        #expect(store.balance(for: account, on: .devnet)?.status == .off(isRegistered: false))
        #expect(!model.isTurnedOn)
        #expect(!model.isTurningOn)
    }

    /// Another failure, such as a rate-limited registration check, fails turning on with a typed error.
    @Test
    func `Other failures fail turning on`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered],
                                                   error: .http(statusCode: 429, retryAfter: nil))
        let store = try PrivateBalanceStore.fixture(responses)
        let model = PrivateBalanceModel()
        await store.refresh(account, on: .devnet)

        model.turnOn()
        await model.run(model.attempt, in: store, for: account, on: .devnet)

        #expect(model.error == .turnOnFailed)
        #expect(!model.isTurnedOn)
    }

    /// A second request while one waits keeps the first attempt, and a stale attempt runs nothing.
    @Test
    func `One attempt runs at a time`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let recovery = try PrivateBalanceFixtures.recoveryStore()
        let store = try PrivateBalanceStore.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]),
                                                    recovery: recovery)
        let model = PrivateBalanceModel()
        await store.refresh(account, on: .devnet)

        model.turnOn()
        let first = model.attempt
        model.turnOn()
        await model.run(UUID(), in: store, for: account, on: .devnet)

        #expect(model.attempt == first)
        #expect(await recovery.reads.isEmpty)
    }
}
