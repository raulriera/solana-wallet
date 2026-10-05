import Foundation
import Testing
@testable import widgets

/// Verifies startup reads preserve wallet identities, storage, and independent window state.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WindowStartupTests {
    /// New window instances reopen the first saved account without changing any stored bytes.
    @Test
    func `Saved wallets survive reopening in independent windows`() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try Account.fixture(index: 0)
        let second = try Account.fixture(index: 1)
        let store = try AccountStore(directory: directory)
        _ = try await store.add(first)
        _ = try await store.add(second)
        let file = directory.appendingPathComponent("accounts.json")
        let original = try Data(contentsOf: file)
        let firstWindow = WindowRouter(initialDestination: .restoringWallets)
        let secondWindow = WindowRouter(initialDestination: .restoringWallets)

        for router in [firstWindow, secondWindow] {
            let reopened = try AccountStore(directory: directory)
            await WindowStartup(accounts: reopened, router: router).restore()
            #expect(router.destination == .wallet(first))
        }
        firstWindow.route(to: .wallet(second))
        #expect(secondWindow.destination == .wallet(first))
        #expect(try Data(contentsOf: file) == original)
    }

    /// An empty installation opens onboarding without creating storage.
    @Test
    func `An empty account store opens onboarding without writing files`() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let router = WindowRouter(initialDestination: .restoringWallets)
        await WindowStartup(accounts: try AccountStore(directory: directory), router: router).restore()

        #expect(router.destination == .onboarding)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    /// Malformed metadata remains available for recovery and must never masquerade as an empty wallet.
    @Test
    func `Unreadable wallet storage shows an error without resetting its contents`() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("accounts.json")
        let original = Data("unreadable-account-records".utf8)
        try original.write(to: file)
        let router = WindowRouter(initialDestination: .restoringWallets)

        await WindowStartup(accounts: try AccountStore(directory: directory), router: router).restore()

        #expect(router.destination == .walletRestorationFailed)
        #expect(try Data(contentsOf: file) == original)
    }

    /// An explicit retry reads the repaired store instead of creating a replacement wallet.
    @Test
    func `Retrying a failed read opens the existing saved wallet`() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let saved = try Account.fixture(index: 0)
        let store = try AccountStore(directory: directory)
        _ = try await store.add(saved)
        let file = directory.appendingPathComponent("accounts.json")
        let original = try Data(contentsOf: file)
        try Data("temporarily-unreadable".utf8).write(to: file)
        let router = WindowRouter(initialDestination: .restoringWallets)
        let startup = WindowStartup(accounts: store, router: router)
        await startup.restore()
        try #require(router.destination == .walletRestorationFailed)

        // Only the fixture repairs its file; startup must leave the recovered bytes intact.
        try original.write(to: file)
        await startup.restore()

        #expect(router.destination == .wallet(saved))
        #expect(try Data(contentsOf: file) == original)
    }

    /// Late results and errors from a cancelled read cannot select onboarding or publish a failure.
    /// - Parameter fails: Whether the cancelled dependency returns data or throws.
    @Test(arguments: [false, true])
    func `Cancelled startup does not publish a late destination`(fails: Bool) async {
        let gate = Suspension()
        let store = StartupAccountStore {
            await gate.suspend()
            if fails { throw CocoaError(.fileReadNoPermission) }
            return []
        }
        let router = WindowRouter(initialDestination: .restoringWallets)
        let startup = WindowStartup(accounts: store, router: router)
        let operation = Task { await startup.restore() }
        defer { operation.cancel() }
        await gate.waitUntilStarted()
        operation.cancel()
        await operation.value

        #expect(router.destination == .restoringWallets)
    }

    /// Reappearing windows preserve both unfinished onboarding and an already selected wallet.
    /// - Parameter hasWallet: Whether the window is in onboarding or already shows a wallet.
    @Test(arguments: [false, true])
    func `Repeated startup preserves resolved window navigation`(hasWallet: Bool) async throws {
        let destination: WindowDestination = try hasWallet ? .wallet(.fixture(index: 0)) : .onboarding
        let router = WindowRouter(initialDestination: destination)
        let store = StartupAccountStore {
            Issue.record("A resolved window must not reload its initial selection")
            return []
        }

        await WindowStartup(accounts: store, router: router).restore()

        #expect(router.destination == destination)
    }

    /// A selection made while a store is suspended wins over its late initial result.
    @Test
    func `A late startup read cannot replace a newer wallet selection`() async throws {
        let started = AsyncStream<Void>.makeStream()
        let pending = AsyncStream<Void>.makeStream()
        let store = StartupAccountStore {
            started.continuation.finish()
            for await _ in pending.stream {}
            return []
        }
        let router = WindowRouter(initialDestination: .restoringWallets)
        let startup = WindowStartup(accounts: store, router: router)
        let operation = Task { await startup.restore() }
        defer { operation.cancel(); pending.continuation.finish() }
        for await _ in started.stream {}
        let selected = try Account.fixture(index: 0)
        router.route(to: .wallet(selected))
        pending.continuation.finish()
        await operation.value

        #expect(router.destination == .wallet(selected))
    }

    /// Creates an isolated directory that cannot contain app wallet data.
    /// - Returns: A unique empty directory.
    /// - Throws: A filesystem error.
    private func temporaryDirectory() throws -> URL {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}
