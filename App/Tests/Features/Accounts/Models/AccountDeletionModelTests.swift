import Foundation
import Testing
@testable import widgets

/// Checks how Settings > Accounts deletes an account the person confirmed, with public metadata only.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AccountDeletionModelTests {
    /// A confirmed deletion removes the account and saves the rest.
    @Test
    func `A deletion removes the account`() async throws {
        let first = try widgets.Account.fixture(index: 0)
        let second = try widgets.Account.fixture(index: 1, recoveryID: first.recoveryID)
        let storage = StoredValue([first, second])
        let store = AccountStore.inMemory(storage)
        await store.load()
        let model = AccountDeletionModel()

        model.delete(second.id)
        await model.run(model.attempt, store: store)

        #expect(store.accounts == [first])
        #expect(await storage.value == [first])
        #expect(model.attempt == nil)
        #expect(model.error == nil)
    }

    /// Confirmations while a deletion waits are ignored, and the deletion runs once.
    @Test
    func `Confirmations while a deletion waits are ignored`() async throws {
        let first = try widgets.Account.fixture(index: 0)
        let second = try widgets.Account.fixture(index: 1, recoveryID: first.recoveryID)
        let store = AccountStore.inMemory(StoredValue([first, second]))
        await store.load()
        let model = AccountDeletionModel()

        model.delete(second.id)
        let attempt = model.attempt
        model.delete(first.id)
        #expect(model.attempt == attempt)
        await model.run(attempt, store: store)
        await model.run(attempt, store: store)

        #expect(store.accounts == [first])
    }

    /// A deletion that can't be saved keeps the account and explains why.
    @Test
    func `A failed deletion explains why`() async throws {
        let first = try widgets.Account.fixture(index: 0)
        let store = AccountStore.inMemory(StoredValue([first], failsSaving: true))
        await store.load()
        let model = AccountDeletionModel()

        model.delete(first.id)
        await model.run(model.attempt, store: store)

        #expect(model.error == .notDeleted)
        #expect(store.accounts == [first])
    }
}
