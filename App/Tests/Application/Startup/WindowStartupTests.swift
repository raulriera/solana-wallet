import Foundation
import Storage
import Testing
@testable import widgets

/// Verifies startup reads preserve wallet identities, storage, and independent window state.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WindowStartupTests {
    /// Windows that share the accounts open the first saved account from one read, without changing what's saved.
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

    /// A window reopens the account it showed before the system ended the app, not the first saved one.
    @Test
    func `A restored window reopens its own saved account`() async throws {
        let saved = try [Account.fixture(index: 0), Account.fixture(index: 1)]
        let window = WindowModel(accounts: .inMemory(StoredValue(saved)))

        await window.restore(preferring: .init(saved[1]))

        #expect(window.destination == .wallet(saved[1]))
    }

    /// A restored account that is no longer saved opens its wallet's first account, not another wallet's.
    @Test
    func `A restored account that is no longer saved opens its wallet's first account`() async throws {
        let other = try Account.fixture(index: 0)
        let walletFirst = try Account.fixture(index: 1)
        let deleted = try Account.fixture(index: 2, recoveryID: walletFirst.recoveryID)
        let window = WindowModel(accounts: .inMemory(StoredValue([other, walletFirst])))

        await window.restore(preferring: .init(deleted))

        #expect(window.destination == .wallet(walletFirst))
    }

    /// A restored account whose wallet is no longer saved opens the first saved account.
    @Test
    func `A restored wallet that is no longer saved opens the first saved account`() async throws {
        let saved = try [Account.fixture(index: 0), Account.fixture(index: 1)]
        let window = WindowModel(accounts: .inMemory(StoredValue(saved)))

        await window.restore(preferring: .init(accountID: UUID(), walletID: UUID()))

        #expect(window.destination == .wallet(saved[0]))
    }

    /// An empty installation opens onboarding without saving anything.
    @Test
    func `An empty account store opens onboarding without saving accounts`() async {
        let storage = StoredValue<[Account]>()
        let window = WindowModel(accounts: .inMemory(storage))

        await window.restore(preferring: nil)

        #expect(window.destination == .onboarding)
        #expect(await storage.value == nil)
    }

    /// A failed launch cleanup never lets a window read wallets or open onboarding past it.
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

    /// Unreadable accounts must never masquerade as an empty wallet.
    @Test
    func `Unreadable wallet storage shows an error without resetting its contents`() async throws {
        let saved = try [Account.fixture(index: 0)]
        let storage = StoredValue(saved, unreadable: true)
        let window = WindowModel(accounts: .inMemory(storage))

        await window.restore(preferring: nil)

        #expect(window.destination == .walletRestorationFailed)
        #expect(await storage.value == saved)
    }

    /// An explicit retry reads the repaired file instead of creating a replacement wallet.
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

        // Only the test repairs its file; startup must leave the recovered bytes intact.
        try original.write(to: file)
        await window.restore(preferring: nil)

        #expect(window.destination == .wallet(saved))
        #expect(try Data(contentsOf: file) == original)
    }

    /// Late results and errors from a cancelled startup cannot select onboarding or publish a failure.
    /// - Parameter fails: Whether the launch cleanup fails after the cancellation.
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

    /// A window in onboarding keeps it when startup runs again after another window saved a wallet.
    @Test
    func `Repeated startup keeps a window in onboarding`() async throws {
        let accounts = AccountStore.inMemory()
        let window = WindowModel(accounts: accounts)
        await window.restore(preferring: nil)
        try await accounts.add(.fixture(index: 0))

        await window.restore(preferring: nil)

        #expect(window.destination == .onboarding)
    }

    /// A selection made while startup waits wins over its late initial result.
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
