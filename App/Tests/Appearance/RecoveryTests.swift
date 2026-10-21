import Foundation
import Synchronization
import Testing
import Themes
@testable import widgets

@MainActor @Suite(.timeLimit(.minutes(1)))
struct AppearanceRecoveryTests {
    /// The shipped Settings resource and recovery service agree on the disabled-by-default switch.
    @Test func `Settings bundle contains recovery switch`() throws {
        let url = try #require(Bundle.main.url(forResource: "Root", withExtension: "plist", subdirectory: "Settings.bundle"))
        let root = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        let items = try #require(root["PreferenceSpecifiers"] as? [[String: Any]])
        let toggle = try #require(items.first { $0["Key"] as? String == SettingsRecoveryRequest.key })
        #expect(toggle["Type"] as? String == "PSToggleSwitchSpecifier")
        #expect(toggle["DefaultValue"] as? Bool == false)
    }

    /// Normal activation preserves selections when Settings has no pending request.
    @Test func `Activation without request loads existing appearance`() async throws {
        let files = try CatalogFixture()
        let preferences = RecoveryFixture()
        defer { files.remove(); preferences.remove() }
        let catalog = ThemeCatalog(directory: files.directory)
        let entry = try await catalog.install(PackService().read(from: files.source()))
        let store = AppearanceStore(directory: files.directory)
        let before = try await store.select(entry.id, for: .application)
        let request = SettingsRecoveryRequest(suiteName: preferences.suiteName)
        let coordinator = AppearanceCoordinator(store: store, recovery: request)
        try await coordinator.activate()
        #expect(coordinator.snapshot == before)
        #expect(try await request.isRequested() == false)
    }

    /// Recovery clears app and wallet selections, retains packs, and does not need readable artwork.
    @Test func `Requested reset restores original appearance once`() async throws {
        let files = try CatalogFixture()
        let preferences = RecoveryFixture()
        defer { files.remove(); preferences.remove() }
        let catalog = ThemeCatalog(directory: files.directory)
        let entry = try await catalog.install(PackService().read(from: files.source()))
        let store = AppearanceStore(directory: files.directory)
        _ = try await store.select(entry.id, for: .application)
        _ = try await store.select(entry.id, for: .wallet(UUID()))
        // Recovery must not depend on decoding a damaged selected package.
        let manifest = CatalogFiles.package(for: entry, in: files.directory).appendingPathComponent("manifest.json")
        try Data("invalid".utf8).write(to: manifest)
        let request = SettingsRecoveryRequest(suiteName: preferences.suiteName)
        try preferences.defaults().set(true, forKey: SettingsRecoveryRequest.key)
        let coordinator = AppearanceCoordinator(store: store, recovery: request)
        try await coordinator.activate()
        #expect(coordinator.snapshot?.preferences == AppearancePreferences())
        #expect(coordinator.snapshot?.entries[entry.id] == entry)
        #expect(try await request.isRequested() == false)
        #expect(FileManager.default.fileExists(atPath: manifest.path))

        try await coordinator.select(entry.id, for: .application)
        let selected = coordinator.snapshot
        let relaunched = AppearanceCoordinator(store: store, recovery: request)
        try await relaunched.activate()
        #expect(relaunched.snapshot == selected)
        try preferences.defaults().set(true, forKey: SettingsRecoveryRequest.key)
        try await relaunched.activate()
        #expect(relaunched.snapshot?.preferences == AppearancePreferences())
        #expect(try await request.isRequested() == false)
    }

    /// A failed reset preserves the switch and displayed state until a later activation succeeds.
    @Test func `Failed reset retains request for next activation`() async throws {
        let files = try CatalogFixture()
        let preferences = RecoveryFixture()
        defer { files.remove(); preferences.remove() }
        let catalog = ThemeCatalog(directory: files.directory)
        let entry = try await catalog.install(PackService().read(from: files.source()))
        let store = AppearanceStore(directory: files.directory)
        let before = try await store.select(entry.id, for: .application)
        let request = SettingsRecoveryRequest(suiteName: preferences.suiteName)
        let coordinator = AppearanceCoordinator(store: store, recovery: request)
        try await coordinator.activate()
        try preferences.defaults().set(true, forKey: SettingsRecoveryRequest.key)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: files.directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: files.directory.path) }
        await #expect(throws: (any Error).self) { try await coordinator.activate() }
        #expect(coordinator.snapshot == before)
        #expect(try await request.isRequested())
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: files.directory.path)
        try await coordinator.activate()
        #expect(coordinator.snapshot?.preferences == AppearancePreferences())
        #expect(try await request.isRequested() == false)
        #expect(try await catalog.pack(for: entry).id == entry.id)
    }

    /// Two activating windows share one recovery operation even if one window's task is cancelled.
    @Test func `Concurrent activations share recovery and survive window cancellation`() async throws {
        let files = try CatalogFixture()
        let preferences = RecoveryFixture()
        defer { files.remove(); preferences.remove() }
        try preferences.defaults().set(true, forKey: SettingsRecoveryRequest.key)
        let request = SettingsRecoveryRequest(suiteName: preferences.suiteName)
        let entered = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let secondEntered = AsyncStream<Void>.makeStream()
        let reads = Mutex(0)
        defer { release.continuation.finish() }
        let intercepted = InterceptedRecoveryRequest(base: request) {
            reads.withLock { $0 += 1 }
            entered.continuation.finish()
            for await _ in release.stream {}
        }
        let coordinator = AppearanceCoordinator(store: AppearanceStore(directory: files.directory), recovery: intercepted)
        let first = Task { try await coordinator.activate() }
        defer { first.cancel() }
        for await _ in entered.stream {}
        let second = Task {
            secondEntered.continuation.finish()
            try await coordinator.activate()
        }
        defer { second.cancel() }
        for await _ in secondEntered.stream {}
        first.cancel()
        release.continuation.finish()
        try await first.value
        try await second.value
        #expect(reads.withLock { $0 } == 1)
        #expect(coordinator.snapshot?.preferences == AppearancePreferences())
        #expect(try await request.isRequested() == false)
    }

    /// A new user selection waits for pending recovery so the reset cannot erase that choice later.
    @Test func `Selection waits for pending recovery`() async throws {
        let files = try CatalogFixture()
        let preferences = RecoveryFixture()
        defer { files.remove(); preferences.remove() }
        let catalog = ThemeCatalog(directory: files.directory)
        let entry = try await catalog.install(PackService().read(from: files.source()))
        let store = AppearanceStore(directory: files.directory)
        try preferences.defaults().set(true, forKey: SettingsRecoveryRequest.key)
        let entered = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let selectionEntered = AsyncStream<Void>.makeStream()
        defer { release.continuation.finish() }
        let request = InterceptedRecoveryRequest(base: SettingsRecoveryRequest(suiteName: preferences.suiteName)) {
            entered.continuation.finish()
            for await _ in release.stream {}
        }
        let coordinator = AppearanceCoordinator(store: store, recovery: request)
        let activating = Task { try await coordinator.activate() }
        defer { activating.cancel() }
        for await _ in entered.stream {}
        let selecting = Task {
            selectionEntered.continuation.finish()
            try await coordinator.select(entry.id, for: .application)
        }
        defer { selecting.cancel() }
        for await _ in selectionEntered.stream {}
        #expect(try await store.load().preferences == AppearancePreferences())
        release.continuation.finish()
        try await activating.value
        try await selecting.value
        #expect(coordinator.snapshot?.theme(for: nil) == entry)
        #expect(try await store.load() == coordinator.snapshot)
    }
}
