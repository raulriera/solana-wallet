import Foundation
import Testing
import Themes
@testable import widgets

@MainActor @Suite(.timeLimit(.minutes(1)))
struct AppearanceCoordinationTests {
    /// A delayed read cannot replace a newer committed selection from another window.
    @Test func olderLoadCannotRollBackNewSelection() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = try ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let store = try AppearanceStore(directory: fixture.directory)
        let loaded = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        defer { release.continuation.finish() }
        let coordinator: any AppearanceCoordinating = AppearanceCoordinator(store: InterceptedAppearanceStore(base: store) {
            loaded.continuation.finish()
            for await _ in release.stream {}
        })
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

    /// Failed persistence leaves all windows displaying the last committed selection.
    @Test func failedSelectionPreservesCachedState() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let store = try AppearanceStore(directory: fixture.directory)
        let coordinator = AppearanceCoordinator(store: store)
        try await coordinator.reload()
        let before = coordinator.snapshot
        await #expect(throws: ThemeCatalog.Failure.changed) { try await coordinator.select(UUID(), for: .application) }
        #expect(coordinator.snapshot == before)
    }

    /// Cached window lookups never read storage; explicit reload publishes deletion fallbacks.
    @Test func cachedSelectionNeedsNoFilesystemAccess() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = try ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let coordinator = AppearanceCoordinator(store: try AppearanceStore(directory: fixture.directory))
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
