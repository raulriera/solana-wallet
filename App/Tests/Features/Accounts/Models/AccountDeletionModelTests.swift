import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AccountDeletionModelTests {
    @Test
    func `A deletion removes the account`() async throws {
        let first = try widgets.Account.fixture(index: 0)
        let second = try widgets.Account.fixture(index: 1)
        let storage = StoredValue([first, second])
        let store = AccountStore.inMemory(storage)
        await store.load()
        let model = AccountDeletionModel()

        model.delete(second.id)
        await model.run(model.attempt, store: store, transactions: .unused)

        #expect(store.accounts == [first])
        #expect(await storage.value == [first])
        #expect(model.attempt == nil)
        #expect(model.error == nil)
    }

    @Test
    func `A deletion erases the account's records`() async throws {
        let first = try widgets.Account.fixture(index: 0)
        let second = try widgets.Account.fixture(index: 1)
        let store = AccountStore.inMemory(StoredValue([first, second]))
        await store.load()
        let pending = StoredValue(Self.records(of: [first, second]))
        let model = AccountDeletionModel()

        model.delete(second.id)
        await model.run(model.attempt, store: store, transactions: .inMemory(pending))

        let kept = try #require(await pending.value)
        #expect(kept.count == Network.allCases.count)
        #expect(kept.allSatisfy { $0.account == first.id })
    }

    @Test
    func `Confirmations while a deletion waits are ignored`() async throws {
        let first = try widgets.Account.fixture(index: 0)
        let second = try widgets.Account.fixture(index: 1)
        let store = AccountStore.inMemory(StoredValue([first, second]))
        await store.load()
        let model = AccountDeletionModel()

        model.delete(second.id)
        let attempt = model.attempt
        model.delete(first.id)
        #expect(model.attempt == attempt)
        await model.run(attempt, store: store, transactions: .unused)
        await model.run(attempt, store: store, transactions: .unused)

        #expect(store.accounts == [first])
    }

    @Test
    func `A failed deletion explains why and keeps the account and its records`() async throws {
        let first = try widgets.Account.fixture(index: 0)
        let store = AccountStore.inMemory(StoredValue([first], failsSaving: true))
        await store.load()
        let pending = StoredValue(Self.records(of: [first]))
        let model = AccountDeletionModel()

        model.delete(first.id)
        await model.run(model.attempt, store: store, transactions: .inMemory(pending))

        #expect(model.error == .notDeleted)
        #expect(store.accounts == [first])
        #expect(await pending.value == Self.records(of: [first]))
    }

    private static func records(of accounts: [widgets.Account]) -> [TransactionRecord] {
        accounts.flatMap { account in
            Network.allCases.map { .fixture(.payment, account: account.id, network: $0) }
        }
    }
}
