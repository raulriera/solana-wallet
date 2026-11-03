import Foundation
import Testing
import Themes
@testable import widgets

@MainActor @Suite(.timeLimit(.minutes(1)))
struct AppearanceCoordinationTests {
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
        try await coordinator.select(entry.id)
        let current = try #require(coordinator.snapshot)
        release.continuation.finish()
        try await pending.value
        #expect(coordinator.snapshot == current)
        #expect(coordinator.snapshot?.theme == entry)
    }

    @Test func `Forgetting a theme publishes its cleared selection`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let coordinator = AppearanceCoordinator(store: AppearanceStore(directory: fixture.directory), recovery: nil)
        try await coordinator.select(entry.id)

        try await coordinator.forget(entry.id)

        #expect(coordinator.snapshot?.theme == nil)
    }

    @Test func `Restarting after the folder is deleted drops the cached selection`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let coordinator = AppearanceCoordinator(store: AppearanceStore(directory: fixture.directory), recovery: nil)
        try await coordinator.select(entry.id)
        try FileManager.default.removeItem(at: fixture.directory)

        try await coordinator.reload()
        #expect(coordinator.snapshot?.theme == entry)
        try await coordinator.restart()

        #expect(coordinator.snapshot?.theme == nil)
        #expect(coordinator.snapshot?.entries.isEmpty == true)
    }

    @Test func `Failed selection preserves cached state`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let store = AppearanceStore(directory: fixture.directory)
        let coordinator = AppearanceCoordinator(store: store, recovery: nil)
        try await coordinator.reload()
        let before = coordinator.snapshot
        await #expect(throws: ThemeCatalogError.changed) { try await coordinator.select(UUID()) }
        #expect(coordinator.snapshot == before)
    }

    @Test func `Cached selection needs no filesystem access`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let coordinator = AppearanceCoordinator(store: AppearanceStore(directory: fixture.directory), recovery: nil)
        try await coordinator.select(entry.id)
        try await catalog.remove(entry)
        #expect(coordinator.snapshot?.theme == entry)
        try await coordinator.reload()
        #expect(coordinator.snapshot?.theme == nil)
        try await coordinator.reset()
        #expect(coordinator.snapshot?.preferences == AppearancePreferences())
    }
}
