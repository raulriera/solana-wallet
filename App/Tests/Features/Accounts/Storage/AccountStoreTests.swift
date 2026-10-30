import Foundation
import Storage
import Testing
import Wallet
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AccountStoreTests {
    @Test
    func `The store reads nothing until it loads`() async {
        let storage = StoredValue<[widgets.Account]>()
        let cleanup = StartupRecoveryCleanup()

        let accounts = AccountStore.inMemory(storage, cleanup: cleanup)

        #expect(accounts.phase == .unloaded)
        #expect(await storage.loads == 0)
        #expect(await cleanup.completions == 0)
    }

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

    @Test
    func `A failed cleanup leaves the accounts unreadable`() async throws {
        let storage = StoredValue(try [widgets.Account.fixture(index: 0)])
        let accounts = AccountStore.inMemory(storage, cleanup: StartupRecoveryCleanup(error: CocoaError(.fileWriteUnknown)))

        await accounts.load()

        #expect(accounts.phase == .unreadable)
        #expect(accounts.accounts.isEmpty)
        #expect(await storage.loads == 0)
    }

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

    @Test
    func `A rename saves the new name`() async throws {
        let first = try widgets.Account.fixture(index: 0)
        let second = try widgets.Account.fixture(index: 1, recoveryID: first.recoveryID)
        let storage = StoredValue([first, second])
        let accounts = AccountStore.inMemory(storage)
        await accounts.load()

        try await accounts.rename(second.id, to: "  Savings ")

        #expect(accounts.accounts.map(\.name) == ["Account 1", "Savings"])
        #expect(await storage.value?.map(\.customName) == [nil, "Savings"])
    }

    @Test
    func `An empty name restores the numbered name`() async throws {
        var account = try widgets.Account.fixture(index: 1)
        account.customName = "Savings"
        let storage = StoredValue([account])
        let accounts = AccountStore.inMemory(storage)
        await accounts.load()

        try await accounts.rename(account.id, to: " ")

        #expect(accounts.accounts.first?.name == "Account 2")
        #expect(await storage.value?.first?.customName == nil)
    }

    @Test(arguments: [
        ([], 0), (["m/44'/501'/0'/0'"], 1), (["m/44'/501'/0'/0'", "m/44'/501'/2'/0'"], 1), (["m/44'/501'/0'"], 1),
        (["m/44'/501'/0'", "m/44'/501'/1'/0'"], 2), (["m/44'/60'/0'/0'"], 0),
    ] as [([String], UInt32)])
    func `The next account takes the lowest unused index`(paths: [String], index: UInt32) async throws {
        let recoveryID = UUID()
        let saved = try paths.enumerated().map { offset, path in
            try widgets.Account(id: UUID(), recoveryID: recoveryID,
                                address: widgets.Account.fixture(index: UInt8(offset)).address,
                                path: DerivationPath(path))
        }
        let other = try widgets.Account.fixture(index: 9)
        let accounts = AccountStore.inMemory(StoredValue(saved + [other]))
        await accounts.load()

        #expect(accounts.nextPath(inWallet: recoveryID) == .solana(account: index))
    }

    @Test
    func `Deleting removes the account`() async throws {
        let first = try widgets.Account.fixture(index: 0)
        let second = try widgets.Account.fixture(index: 1, recoveryID: first.recoveryID)
        let storage = StoredValue([first, second])
        let accounts = AccountStore.inMemory(storage)
        await accounts.load()

        try await accounts.remove(second.id)

        #expect(accounts.accounts == [first])
        #expect(await storage.value == [first])
    }

    @Test
    func `A deleted account's index is used again`() async throws {
        let first = try widgets.Account.fixture(index: 0)
        let second = try widgets.Account.fixture(index: 1, recoveryID: first.recoveryID)
        let accounts = AccountStore.inMemory(StoredValue([first, second]))
        await accounts.load()

        try await accounts.remove(second.id)

        #expect(accounts.nextPath(inWallet: first.recoveryID) == .solana(account: 1))
    }

    @Test(arguments: Change.allCases)
    func `A change to an unsaved account changes nothing`(_ change: Change) async throws {
        let first = try widgets.Account.fixture(index: 0)
        let storage = StoredValue([first])
        let accounts = AccountStore.inMemory(storage)
        await accounts.load()

        try await change.apply(to: UUID(), in: accounts)

        #expect(accounts.accounts == [first])
        #expect(await storage.value == [first])
    }

    @Test(arguments: Change.allCases)
    func `A failed change is undone`(_ change: Change) async throws {
        let first = try widgets.Account.fixture(index: 0)
        let storage = StoredValue([first], failsSaving: true)
        let accounts = AccountStore.inMemory(storage)
        await accounts.load()

        await #expect(throws: CocoaError.self) { try await change.apply(to: first.id, in: accounts) }

        #expect(accounts.accounts == [first])
        #expect(await storage.value == [first])
    }

    enum Change: CaseIterable {
        case rename
        case deletion

        @MainActor
        func apply(to id: widgets.Account.ID, in accounts: AccountStore) async throws {
            switch self {
            case .rename: try await accounts.rename(id, to: "Savings")
            case .deletion: try await accounts.remove(id)
            }
        }
    }
}
