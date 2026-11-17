import Foundation
import Storage
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WindowStartupTests {
    @Test
    func `Saved wallets survive reopening in independent windows`() async throws {
        let first = try Account.fixture(index: 0)
        let second = try Account.fixture(index: 1)
        let storage = StoredValue([first, second])
        let accounts = AccountStore.inMemory(storage)
        let firstWindow = WindowModel(accounts: accounts)
        let secondWindow = WindowModel(accounts: accounts)

        for window in [firstWindow, secondWindow] {
            await window.restore(preferring: nil)
            #expect(window.destination == .wallet(first))
        }
        firstWindow.account = second
        #expect(secondWindow.destination == .wallet(first))
        #expect(await storage.value == [first, second])
        #expect(await storage.loads == 1)
    }

    @Test
    func `A restored window reopens its saved account, or the first saved account if it's gone`() async throws {
        let saved = try [Account.fixture(index: 0), Account.fixture(index: 1)]
        let restored = WindowModel(accounts: .inMemory(StoredValue(saved)))
        let removed = WindowModel(accounts: .inMemory(StoredValue(saved)))

        await restored.restore(preferring: saved[1].id)
        await removed.restore(preferring: UUID())

        #expect(restored.destination == .wallet(saved[1]))
        #expect(removed.destination == .wallet(saved[0]))
    }

    @Test
    func `An empty account store opens onboarding without saving accounts`() async {
        let storage = StoredValue<[Account]>()
        let window = WindowModel(accounts: .inMemory(storage))

        await window.restore(preferring: nil)

        #expect(window.destination == .onboarding)
        #expect(await storage.value == nil)
    }

    @Test
    func `A failed launch cleanup shows an error before any wallet is read`() async throws {
        let storage = StoredValue<[Account]>()
        let cleanup = StartupRecoveryCleanup(error: CocoaError(.fileReadNoPermission))
        let window = WindowModel(accounts: .inMemory(storage, cleanup: cleanup))

        await window.restore(preferring: nil)

        #expect(window.destination == .walletRestorationFailed)
        #expect(await cleanup.completions == 1)
        #expect(await storage.loads == 0)
    }

    @Test
    func `Unreadable wallet storage shows an error without resetting its contents`() async throws {
        let saved = try [Account.fixture(index: 0)]
        let storage = StoredValue(saved, unreadable: true)
        let window = WindowModel(accounts: .inMemory(storage))

        await window.restore(preferring: nil)

        #expect(window.destination == .walletRestorationFailed)
        #expect(await storage.value == saved)
    }

    @Test
    func `Retrying a failed read opens the existing saved wallet`() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let saved = try Account.fixture(index: 0)
        let storage = AccountStore.file(in: directory)
        let file = storage.url
        let original = try AccountsCoding().encode([saved])
        try Data("temporarily-unreadable".utf8).write(to: file)
        let window = WindowModel(accounts: AccountStore(storage: storage, cleanup: StartupRecoveryCleanup()))
        await window.restore(preferring: nil)
        try #require(window.destination == .walletRestorationFailed)

        try original.write(to: file)
        await window.restore(preferring: nil)

        #expect(window.destination == .wallet(saved))
        #expect(try Data(contentsOf: file) == original)
    }

    @Test(arguments: [false, true])
    func `Cancelled startup does not publish a late destination`(fails: Bool) async {
        let gate = Suspension()
        let cleanup = StartupRecoveryCleanup(error: fails ? CocoaError(.fileReadNoPermission) : nil, gate: gate)
        let window = WindowModel(accounts: .inMemory(cleanup: cleanup))
        let operation = Task { await window.restore(preferring: nil) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()
        operation.cancel()
        gate.resume()
        await operation.value

        #expect(window.destination == .restoringWallets)
    }

    @Test
    func `Repeated startup keeps a window in onboarding`() async throws {
        let accounts = AccountStore.inMemory()
        let window = WindowModel(accounts: accounts)
        await window.restore(preferring: nil)
        try await accounts.add(.fixture(index: 0))

        await window.restore(preferring: nil)

        #expect(window.destination == .onboarding)
    }

    @Test
    func `A late startup read cannot replace a newer wallet selection`() async throws {
        let gate = Suspension()
        let saved = try [Account.fixture(index: 0), Account.fixture(index: 1)]
        let window = WindowModel(accounts: .inMemory(StoredValue(saved), cleanup: StartupRecoveryCleanup(gate: gate)))
        let operation = Task { await window.restore(preferring: nil) }
        defer { operation.cancel(); gate.resume() }
        await gate.waitUntilStarted()
        window.account = saved[1]
        gate.resume()
        await operation.value

        #expect(window.destination == .wallet(saved[1]))
    }
}
