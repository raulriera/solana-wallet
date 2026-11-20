import Foundation
import Portfolio
import Privacy
import RPC
import Testing
import Transactions
@testable import widgets

@MainActor
struct PrivateBalanceModelTests {
    @Test(arguments: [false, true])
    func `A second sheet keeps the open one`(isMoveFirst: Bool) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let store = try await PrivateBalanceFixtures.store(holding: .available, of: account)
        let model = PrivateBalanceModel()
        await store.refresh(account, on: .devnet)
        let openMove = {
            model.open(.toPrivate, of: PrivateBalanceFixtures.solHolding, in: store, for: account, on: .devnet)
        }
        let sendPrivately = PrivateSendAction(model: model)
        if isMoveFirst { openMove() } else { sendPrivately() }
        let first = try #require(model.sheet)

        if isMoveFirst { sendPrivately() } else { openMove() }

        #expect(model.sheet?.id == first.id)
        #expect(model.sheet?.move?.direction == (isMoveFirst ? .toPrivate : nil))
    }

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
