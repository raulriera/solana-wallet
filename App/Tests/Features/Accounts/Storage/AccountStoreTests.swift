import Foundation
import Storage
import Testing
import Wallet
@testable import widgets

/// Verifies the shared accounts with in-memory storage and public metadata only.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AccountStoreTests {
    /// Creating the store reads nothing and runs no cleanup.
    @Test
    func `The store reads nothing until it loads`() async {
        let storage = StoredValue<[widgets.Account]>()
        let cleanup = StartupRecoveryCleanup()

        let accounts = AccountStore.inMemory(storage, cleanup: cleanup)

        #expect(accounts.phase == .unloaded)
        #expect(await storage.loads == 0)
        #expect(await cleanup.completions == 0)
    }

    /// The launch cleanup finishes before the first read, so no window reads accounts while recovery is deleted.
    @Test
    func `Loading finishes the launch cleanup before reading the accounts`() async throws {
        let saved = try [widgets.Account.fixture(index: 0)]
        let storage = StoredValue(saved)
        let gate = Suspension()
        let accounts = AccountStore.inMemory(storage, cleanup: StartupRecoveryCleanup(gate: gate))
        let loading = Task { await accounts.load() }
        defer { gate.resume() }

        await gate.waitUntilStarted()
        #expect(accounts.phase == .loading)
        #expect(await storage.loads == 0)
        gate.resume()
        await loading.value

        #expect(accounts.phase == .loaded)
        #expect(accounts.accounts == saved)
    }

    /// A failed cleanup leaves the accounts unread and unreadable, so no window opens onboarding past it.
    @Test
    func `A failed cleanup leaves the accounts unreadable`() async throws {
        let storage = StoredValue(try [widgets.Account.fixture(index: 0)])
        let accounts = AccountStore.inMemory(storage, cleanup: StartupRecoveryCleanup(error: CocoaError(.fileWriteUnknown)))

        await accounts.load()

        #expect(accounts.phase == .unreadable)
        #expect(accounts.accounts.isEmpty)
        #expect(await storage.loads == 0)
    }

    /// Unreadable accounts never count as an empty list and are never replaced by an addition.
    @Test
    func `Unreadable accounts are reported and kept`() async throws {
        let saved = try [widgets.Account.fixture(index: 0)]
        let storage = StoredValue(saved, unreadable: true)
        let accounts = AccountStore.inMemory(storage)

        await accounts.load()
        await #expect(throws: KeychainItemError.unreadable) { try await accounts.add(widgets.Account.fixture(index: 1)) }

        #expect(accounts.phase == .unreadable)
        #expect(accounts.accounts.isEmpty)
        #expect(await storage.value == saved)
    }

    /// An addition shows at once and saves after the saved accounts.
    @Test
    func `Adding saves after the saved accounts`() async throws {
        let first = try widgets.Account.fixture(index: 0)
        let second = try widgets.Account.fixture(index: 1, recoveryID: first.recoveryID)
        let storage = StoredValue([first])
        let accounts = AccountStore.inMemory(storage)
        await accounts.load()

        try await accounts.add(second)

        #expect(accounts.accounts == [first, second])
        #expect(await storage.value == [first, second])
    }

    /// Additions made at the same time save every account.
    @Test
    func `Concurrent additions keep every account`() async throws {
        let recoveryID = UUID()
        let added = try (0..<16).map { try widgets.Account.fixture(index: UInt8($0), recoveryID: recoveryID) }
        let storage = StoredValue<[widgets.Account]>()
        let accounts = AccountStore.inMemory(storage)
        await accounts.load()

        try await withThrowingTaskGroup { group in
            for account in added { group.addTask { try await accounts.add(account) } }
            try await group.waitForAll()
        }

        #expect(Set(accounts.accounts.map(\.id)) == Set(added.map(\.id)))
        #expect(await storage.value?.count == added.count)
    }

    /// An account with a saved identity, address, or recovery and path is rejected without changing storage.
    /// - Parameter field: What the addition shares with the saved account.
    @Test(arguments: ["id", "address", "path"])
    func `Duplicate accounts are rejected`(_ field: String) async throws {
        let first = try widgets.Account.fixture(index: 0)
        let other = try widgets.Account.fixture(index: 1, recoveryID: first.recoveryID)
        let storage = StoredValue([first])
        let accounts = AccountStore.inMemory(storage)
        await accounts.load()
        let duplicate = widgets.Account(id: field == "id" ? first.id : other.id, recoveryID: first.recoveryID,
                                        address: field == "address" ? first.address : other.address,
                                        path: field == "path" ? first.path : other.path)

        await #expect(throws: AccountStoreError.duplicateAccount) { try await accounts.add(duplicate) }

        #expect(accounts.accounts == [first])
        #expect(await storage.value == [first])
    }

    /// One wallet keeps both discovery path families at the same index.
    @Test
    func `Both discovery path families of a wallet are saved`() async throws {
        let first = try widgets.Account.fixture(index: 0)
        let second = try widgets.Account(id: UUID(), recoveryID: first.recoveryID, address: widgets.Account.fixture(index: 1).address,
                                         path: DerivationPath("m/44'/501'/0'"))
        let accounts = AccountStore.inMemory()
        await accounts.load()

        try await accounts.add(first)
        try await accounts.add(second)

        #expect(accounts.accounts == [first, second])
    }

    /// An addition that can't be saved is undone and throws.
    @Test
    func `A failed addition is undone`() async throws {
        let first = try widgets.Account.fixture(index: 0)
        let storage = StoredValue([first], failsSaving: true)
        let accounts = AccountStore.inMemory(storage)
        await accounts.load()

        await #expect(throws: CocoaError.self) { try await accounts.add(widgets.Account.fixture(index: 1)) }

        #expect(accounts.accounts == [first])
        #expect(await storage.value == [first])
    }

    /// The file's coding rejects a duplicate that an addition before the first read couldn't check, so the file keeps
    /// its accounts.
    @Test
    func `A duplicate added before the first read is never written`() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = AccountStore.file(in: directory)
        let file = storage.url
        let first = try widgets.Account.fixture(index: 0)
        let original = try AccountsCoding().encode([first])
        try original.write(to: file)
        let accounts = AccountStore(storage: storage, cleanup: StartupRecoveryCleanup())
        let duplicate = try widgets.Account(id: UUID(), recoveryID: UUID(), address: first.address,
                                            path: widgets.Account.fixture(index: 1).path)

        await #expect(throws: FileItemError.unencodable) { try await accounts.add(duplicate) }

        #expect(try Data(contentsOf: file) == original)
    }

    /// A wallet's accounts leave out every other wallet's.
    @Test
    func `A wallet lists only its own accounts`() async throws {
        let first = try widgets.Account.fixture(index: 0)
        let other = try widgets.Account.fixture(index: 1)
        let second = try widgets.Account.fixture(index: 2, recoveryID: first.recoveryID)
        let accounts = AccountStore.inMemory(StoredValue([first, other, second]))
        await accounts.load()

        #expect(accounts.accounts(inWallet: first.recoveryID) == [first, second])
        #expect(accounts.accounts(inWallet: UUID()).isEmpty)
    }

    /// Erasing deletes the saved accounts and empties the list that every window shows.
    @Test
    func `Erasing forgets every account`() async throws {
        let storage = StoredValue(try [widgets.Account.fixture(index: 0)])
        let accounts = AccountStore.inMemory(storage)
        await accounts.load()

        try await accounts.erase()

        #expect(accounts.accounts.isEmpty)
        #expect(accounts.phase == .loaded)
        #expect(await storage.value == nil)
        #expect(await storage.deletions == 1)
    }
}
