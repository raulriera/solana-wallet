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
        let firstWindow = WindowRouter(initialDestination: .restoringWallets)
        let secondWindow = WindowRouter(initialDestination: .restoringWallets)

        for router in [firstWindow, secondWindow] {
            await WindowStartup(accounts: accounts, router: router).restore(preferring: nil)
            #expect(router.destination == .wallet(first))
        }
        firstWindow.route(to: .wallet(second))
        #expect(secondWindow.destination == .wallet(first))
        #expect(await storage.value == [first, second])
        #expect(await storage.loads == 1)
    }

    /// A window reopens the wallet it showed before the system ended the app, not the first saved one.
    @Test
    func `A restored window reopens its own saved wallet`() async throws {
        let saved = try [Account.fixture(index: 0), Account.fixture(index: 1)]
        let router = WindowRouter(initialDestination: .restoringWallets)

        await WindowStartup(accounts: .inMemory(StoredValue(saved)), router: router).restore(preferring: saved[1].id)

        #expect(router.destination == .wallet(saved[1]))
    }

    /// A restored identifier for a wallet that is no longer saved falls back to the first saved wallet.
    @Test
    func `A restored wallet that is no longer saved opens the first saved wallet`() async throws {
        let saved = try [Account.fixture(index: 0), Account.fixture(index: 1)]
        let router = WindowRouter(initialDestination: .restoringWallets)

        await WindowStartup(accounts: .inMemory(StoredValue(saved)), router: router).restore(preferring: UUID())

        #expect(router.destination == .wallet(saved[0]))
    }

    /// An empty installation opens onboarding without saving anything.
    @Test
    func `An empty account store opens onboarding without saving accounts`() async {
        let storage = StoredValue<[Account]>()
        let router = WindowRouter(initialDestination: .restoringWallets)

        await WindowStartup(accounts: .inMemory(storage), router: router).restore(preferring: nil)

        #expect(router.destination == .onboarding)
        #expect(await storage.value == nil)
    }

    /// A failed launch cleanup never lets a window read wallets or open onboarding past it.
    @Test
    func `A failed launch cleanup shows an error before any wallet is read`() async throws {
        let storage = StoredValue<[Account]>()
        let cleanup = StartupRecoveryCleanup(error: CocoaError(.fileReadNoPermission))
        let router = WindowRouter(initialDestination: .restoringWallets)

        await WindowStartup(accounts: .inMemory(storage, cleanup: cleanup), router: router).restore(preferring: nil)

        #expect(router.destination == .walletRestorationFailed)
        #expect(await cleanup.completions == 1)
        #expect(await storage.loads == 0)
    }

    /// Unreadable accounts must never masquerade as an empty wallet.
    @Test
    func `Unreadable wallet storage shows an error without resetting its contents`() async throws {
        let saved = try [Account.fixture(index: 0)]
        let storage = StoredValue(saved, unreadable: true)
        let router = WindowRouter(initialDestination: .restoringWallets)

        await WindowStartup(accounts: .inMemory(storage), router: router).restore(preferring: nil)

        #expect(router.destination == .walletRestorationFailed)
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
        let router = WindowRouter(initialDestination: .restoringWallets)
        let startup = WindowStartup(accounts: AccountStore(storage: storage, cleanup: StartupRecoveryCleanup()),
                                    router: router)
        await startup.restore(preferring: nil)
        try #require(router.destination == .walletRestorationFailed)

        // Only the test repairs its file; startup must leave the recovered bytes intact.
        try original.write(to: file)
        await startup.restore(preferring: nil)

        #expect(router.destination == .wallet(saved))
        #expect(try Data(contentsOf: file) == original)
    }

    /// Late results and errors from a cancelled startup cannot select onboarding or publish a failure.
    /// - Parameter fails: Whether the launch cleanup fails after the cancellation.
    @Test(arguments: [false, true])
    func `Cancelled startup does not publish a late destination`(fails: Bool) async {
        let gate = Suspension()
        let cleanup = StartupRecoveryCleanup(error: fails ? CocoaError(.fileReadNoPermission) : nil, gate: gate)
        let router = WindowRouter(initialDestination: .restoringWallets)
        let startup = WindowStartup(accounts: .inMemory(cleanup: cleanup), router: router)
        let operation = Task { await startup.restore(preferring: nil) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()
        operation.cancel()
        gate.resume()
        await operation.value

        #expect(router.destination == .restoringWallets)
    }

    /// Reappearing windows preserve both unfinished onboarding and an already selected wallet.
    /// - Parameter hasWallet: Whether the window is in onboarding or already shows a wallet.
    @Test(arguments: [false, true])
    func `Repeated startup preserves resolved window navigation`(hasWallet: Bool) async throws {
        let destination: WindowDestination = try hasWallet ? .wallet(.fixture(index: 0)) : .onboarding
        let router = WindowRouter(initialDestination: destination)
        let storage = StoredValue<[Account]>()
        let cleanup = StartupRecoveryCleanup()

        await WindowStartup(accounts: .inMemory(storage, cleanup: cleanup), router: router).restore(preferring: nil)

        #expect(router.destination == destination)
        #expect(await cleanup.completions == 0)
        #expect(await storage.loads == 0)
    }

    /// A selection made while startup waits wins over its late initial result.
    @Test
    func `A late startup read cannot replace a newer wallet selection`() async throws {
        let gate = Suspension()
        let router = WindowRouter(initialDestination: .restoringWallets)
        let startup = WindowStartup(accounts: .inMemory(cleanup: StartupRecoveryCleanup(gate: gate)), router: router)
        let operation = Task { await startup.restore(preferring: nil) }
        defer { operation.cancel(); gate.resume() }
        await gate.waitUntilStarted()
        let selected = try Account.fixture(index: 0)
        router.route(to: .wallet(selected))
        gate.resume()
        await operation.value

        #expect(router.destination == .wallet(selected))
    }
}
