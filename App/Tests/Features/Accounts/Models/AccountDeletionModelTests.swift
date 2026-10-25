import Foundation
import RPC
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
        await model.run(model.attempt, store: store, transactions: .unused)

        #expect(store.accounts == [first])
        #expect(await storage.value == [first])
        #expect(model.attempt == nil)
        #expect(model.error == nil)
    }

    /// A deletion erases the account's transaction records on every network, and keeps the other accounts' records.
    @Test
    func `A deletion erases the account's records`() async throws {
        let first = try widgets.Account.fixture(index: 0)
        let second = try widgets.Account.fixture(index: 1, recoveryID: first.recoveryID)
        let store = AccountStore.inMemory(StoredValue([first, second]))
        await store.load()
        let records = Self.records(of: [first, second])
        let model = AccountDeletionModel()

        model.delete(second.id)
        await model.run(model.attempt, store: store, transactions: .inMemory(records))

        for network in Network.allCases {
            #expect(await records[TransactionRecord.Key(account: second.id, network: network)]?.value == nil)
            #expect(await records[TransactionRecord.Key(account: first.id, network: network)]?.value?.count == 1)
        }
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
        await model.run(attempt, store: store, transactions: .unused)
        await model.run(attempt, store: store, transactions: .unused)

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
        await model.run(model.attempt, store: store, transactions: .unused)

        #expect(model.error == .notDeleted)
        #expect(store.accounts == [first])
    }

    /// A deletion that can't be saved keeps the account's transaction records.
    @Test
    func `A failed deletion keeps the account's records`() async throws {
        let first = try widgets.Account.fixture(index: 0)
        let store = AccountStore.inMemory(StoredValue([first], failsSaving: true))
        await store.load()
        let records = Self.records(of: [first])
        let model = AccountDeletionModel()

        model.delete(first.id)
        await model.run(model.attempt, store: store, transactions: .inMemory(records))

        #expect(await records[TransactionRecord.Key(account: first.id, network: .devnet)]?.value?.count == 1)
    }

    /// Each account's records on each network: one payment each.
    /// - Parameter accounts: The accounts.
    /// - Returns: The in-memory records by account and network.
    private static func records(of accounts: [widgets.Account])
        -> [TransactionRecord.Key: StoredValue<[TransactionRecord]>] {
        var records: [TransactionRecord.Key: StoredValue<[TransactionRecord]>] = [:]
        for account in accounts {
            for network in Network.allCases {
                records[TransactionRecord.Key(account: account.id, network: network)] = StoredValue([
                    .fixture(.payment(recipient: account.address, mint: nil, units: 1), account: account.id,
                             network: network),
                ])
            }
        }
        return records
    }
}
