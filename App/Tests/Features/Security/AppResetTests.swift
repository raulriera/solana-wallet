import Foundation
import RPC
import Storage
import Testing
@testable import widgets

/// Verifies the reset's deletion order, its window signal, and retries, without touching real storage.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AppResetTests {
    /// Secrets go first, the directories before appearance forgets them, and every window hears about the reset only once
    /// everything is deleted.
    @Test
    func `Reset deletes recovery, private balances, the directories, appearance, contacts, accounts, transactions, the API key, then the provider settings`() async throws {
        let storage = ResetStorage()
        defer { try? FileManager.default.removeItem(at: storage.directory) }
        try createFile(in: storage.directory)
        let revision = Revision()

        try await AppReset(storage: storage, revision: revision).reset()

        #expect(await storage.deletions == ResetStorage.Step.allCases)
        #expect(await storage.directoryExisted == [true, true, false, false, false, false, false, false])
        #expect(revision.value == 1)
    }

    /// A failed step stops the reset and keeps windows where they are; trying again finishes it.
    /// - Parameter step: The store whose first deletion fails.
    @Test(arguments: ResetStorage.Step.allCases)
    func `Retrying after a failed step finishes the reset`(_ step: ResetStorage.Step) async throws {
        let storage = ResetStorage(failingOnce: step)
        let revision = Revision()
        let reset = AppReset(storage: storage, revision: revision)
        let order = ResetStorage.Step.allCases

        await #expect(throws: CocoaError.self) { try await reset.reset() }
        #expect(await storage.deletions == Array(order.prefix { $0 != step }))
        #expect(revision.value == 0)

        try await reset.reset()
        #expect(await Array(storage.deletions.suffix(order.count)) == order)
        #expect(revision.value == 1)
    }

    /// A directory that can't be deleted stops the reset before appearance and the provider; trying again finishes it.
    @Test
    func `Retrying after a directory can't be deleted finishes the reset`() async throws {
        let storage = ResetStorage()
        defer { try? FileManager.default.removeItem(at: storage.directory) }
        try createFile(in: storage.directory)
        let revision = Revision()
        let reset = AppReset(storage: storage, revision: revision)
        // A read-only directory keeps the file inside it.
        try setPermissions(0o555, of: storage.directory)

        await #expect(throws: CocoaError.self) { try await reset.reset() }
        #expect(await storage.deletions == [.recovery, .privateBalances])
        #expect(revision.value == 0)

        try setPermissions(0o755, of: storage.directory)
        try await reset.reset()
        #expect(!FileManager.default.fileExists(atPath: storage.directory.path))
        #expect(revision.value == 1)
    }

    /// Windows that show the shared contacts forget them once the reset finishes.
    @Test
    func `Reset empties the contacts that windows show`() async throws {
        let storage = ResetStorage()
        let addressBook = StoredValue(ContactsFixtures.addressBook)
        let contacts = ContactsFixtures.store(addressBook)
        await contacts.load()

        try await AppReset(storage: storage, contacts: contacts, revision: Revision()).reset()

        #expect(contacts.addressBook == AddressBook())
        #expect(await addressBook.value == nil)
    }

    /// Windows that show the shared accounts forget them once the reset finishes.
    @Test
    func `Reset empties the accounts that windows show`() async throws {
        let saved = StoredValue([try widgets.Account.fixture(index: 0)])
        let accounts = AccountStore.inMemory(saved)
        await accounts.load()

        try await AppReset(storage: ResetStorage(), accounts: accounts, revision: Revision()).reset()

        #expect(accounts.accounts.isEmpty)
        #expect(accounts.phase == .loaded)
        #expect(await saved.value == nil)
    }

    /// Windows that show the shared transactions forget their records once the reset finishes.
    @Test
    func `Reset empties the transactions that windows show`() async throws {
        let account = UUID()
        let key = TransactionRecord.Key(account: account, network: .devnet)
        let saved = StoredValue([TransactionRecord.fixture(.privateDeposit(lamports: 1), account: account)])
        let transactions = TransactionStore.inMemory(saved) { _ in throw SubmitterError.noProviders }
        await transactions.load(key)

        try await AppReset(storage: ResetStorage(), transactions: transactions, revision: Revision()).reset()

        #expect(transactions.records(for: key).isEmpty)
        #expect(await saved.value == nil)
    }

    /// Saves one file in a directory, creating the directory.
    /// - Parameter directory: The directory to fill.
    /// - Throws: A filesystem error.
    private func createFile(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("saved".utf8).write(to: directory.appending(path: "file.json"))
    }

    /// Changes who can change a directory's contents.
    /// - Parameters:
    ///   - permissions: The POSIX permissions.
    ///   - directory: The directory to change.
    /// - Throws: A filesystem error.
    private func setPermissions(_ permissions: Int, of directory: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: directory.path)
    }
}
