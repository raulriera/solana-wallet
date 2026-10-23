import Foundation
import Testing
import Themes
@testable import widgets

@MainActor @Suite(.timeLimit(.minutes(1)))
struct AppearanceCoordinationTests {
    /// A delayed read cannot replace a newer committed selection from another window.
    @Test func `Older load cannot roll back new selection`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let store = AppearanceStore(directory: fixture.directory)
        let loaded = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        defer { release.continuation.finish() }
        let coordinator: any AppearanceCoordinating = AppearanceCoordinator(store: InterceptedAppearanceStore(base: store) {
            loaded.continuation.finish()
            for await _ in release.stream {}
        }, recovery: nil)
        let pending = Task { try await coordinator.reload() }
        defer { pending.cancel() }
        for await _ in loaded.stream {}
        try await coordinator.select(entry.id, for: .application)
        let current = try #require(coordinator.snapshot)
        release.continuation.finish()
        try await pending.value
        #expect(coordinator.snapshot == current)
        #expect(coordinator.snapshot?.theme(for: nil) == entry)
    }

    /// Forgetting a theme publishes the cleared selection to every window.
    @Test func `Forgetting a theme publishes its cleared selection`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let coordinator = AppearanceCoordinator(store: AppearanceStore(directory: fixture.directory), recovery: nil)
        try await coordinator.select(entry.id, for: .application)

        try await coordinator.forget(entry.id)

        #expect(coordinator.snapshot?.theme(for: nil) == nil)
    }

    /// After a reset deletes the theme folder, the new state replaces the cached selection despite its lower revision.
    @Test func `Restarting after the folder is deleted drops the cached selection`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let coordinator = AppearanceCoordinator(store: AppearanceStore(directory: fixture.directory), recovery: nil)
        try await coordinator.select(entry.id, for: .application)
        try FileManager.default.removeItem(at: fixture.directory)

        try await coordinator.reload()
        #expect(coordinator.snapshot?.theme(for: nil) == entry)
        try await coordinator.restart()

        #expect(coordinator.snapshot?.theme(for: nil) == nil)
        #expect(coordinator.snapshot?.entries.isEmpty == true)
    }

    /// Failed persistence leaves all windows displaying the last committed selection.
    @Test func `Failed selection preserves cached state`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let store = AppearanceStore(directory: fixture.directory)
        let coordinator = AppearanceCoordinator(store: store, recovery: nil)
        try await coordinator.reload()
        let before = coordinator.snapshot
        await #expect(throws: ThemeCatalogError.changed) { try await coordinator.select(UUID(), for: .application) }
        #expect(coordinator.snapshot == before)
    }

    /// Cached window lookups never read storage; explicit reload publishes deletion fallbacks.
    @Test func `Cached selection needs no filesystem access`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let coordinator = AppearanceCoordinator(store: AppearanceStore(directory: fixture.directory), recovery: nil)
        let wallet = UUID()
        try await coordinator.select(entry.id, for: .wallet(wallet))
        try await catalog.remove(entry)
        #expect(coordinator.snapshot?.theme(for: wallet) == entry)
        try await coordinator.reload()
        #expect(coordinator.snapshot?.theme(for: wallet) == nil)
        #expect(coordinator.snapshot?.preferences.walletThemeIDs.isEmpty == true)
        try await coordinator.reset()
        #expect(coordinator.snapshot?.preferences == AppearancePreferences())
    }
}
