import Foundation
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AccountRenameModelTests {
    @Test
    func `A rename saves the new name`() async throws {
        let account = try widgets.Account.fixture(index: 0)
        let storage = StoredValue([account])
        let store = AccountStore.inMemory(storage)
        await store.load()
        let model = AccountRenameModel()

        model.rename(account.id, to: " Savings ")
        #expect(model.isRenaming)
        await model.run(model.attempt, store: store)

        #expect(model.isRenamed)
        #expect(!model.isRenaming)
        #expect(store.accounts.first?.name == "Savings")
        #expect(await storage.value?.first?.customName == "Savings")
    }

    @Test
    func `Taps while a rename waits are ignored`() async throws {
        let account = try widgets.Account.fixture(index: 0)
        let store = AccountStore.inMemory(StoredValue([account]))
        await store.load()
        let model = AccountRenameModel()

        model.rename(account.id, to: "Savings")
        let attempt = model.attempt
        model.rename(account.id, to: "Spending")
        #expect(model.attempt == attempt)
        await model.run(attempt, store: store)
        await model.run(attempt, store: store)

        #expect(store.accounts.first?.name == "Savings")
    }

    @Test
    func `A new rename starts unsaved`() async throws {
        let account = try widgets.Account.fixture(index: 0)
        let store = AccountStore.inMemory(StoredValue([account]))
        await store.load()
        let model = AccountRenameModel()
        model.rename(account.id, to: "Savings")
        await model.run(model.attempt, store: store)

        model.rename(account.id, to: "Spending")

        #expect(!model.isRenamed)
    }

    @Test
    func `A failed rename explains why`() async throws {
        let account = try widgets.Account.fixture(index: 0)
        let store = AccountStore.inMemory(StoredValue([account], failsSaving: true))
        await store.load()
        let model = AccountRenameModel()

        model.rename(account.id, to: "Savings")
        await model.run(model.attempt, store: store)

        #expect(model.error == .notRenamed)
        #expect(!model.isRenamed)
        #expect(store.accounts == [account])
    }
}
