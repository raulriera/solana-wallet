import Foundation
import Testing
import Themes
@testable import widgets

@MainActor @Suite(.timeLimit(.minutes(1)))
struct AppearanceSettingsTests {
    /// Selection stays visually quiet while persistence completes and still rejects overlapping writes.
    @Test func selectionSavesWithoutTransientActivity() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = try makeSettings(fixture)
        settings.importPack(from: try fixture.source())
        await settings.waitForOperation()
        let entry = try #require(settings.entries.first)
        let before = settings.appearance.snapshot

        settings.select(entry.id, for: .application)
        #expect(settings.activity == nil)
        #expect(settings.appearance.snapshot == before)
        settings.select(nil, for: .application)
        await settings.waitForOperation()

        #expect(settings.appearance.snapshot?.preferences.appThemeID == entry.id)
        #expect(settings.failure == nil)
        #expect(settings.activity == nil)
    }

    /// Import updates shared metadata without changing the app or wallet selection.
    @Test func importInstallsWithoutSelecting() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = try makeSettings(fixture)
        await settings.activate()
        settings.importPack(from: try fixture.source(name: "Imported"))
        await settings.waitForOperation()
        #expect(settings.failure == nil)
        #expect(settings.entries.map(\.name) == ["Imported"])
        #expect(settings.appearance.snapshot?.preferences == AppearancePreferences())
    }

    /// A failed import preserves every installed entry and its selected appearance.
    @Test func invalidImportPreservesSelection() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = try makeSettings(fixture)
        settings.importPack(from: try fixture.source())
        await settings.waitForOperation()
        let entry = try #require(settings.entries.first)
        settings.select(entry.id, for: .application)
        await settings.waitForOperation()
        let before = settings.appearance.snapshot
        let invalid = try fixture.source()
        try Data("{}".utf8).write(to: invalid.appendingPathComponent("manifest.json"))
        settings.importPack(from: invalid)
        await settings.waitForOperation()
        #expect(settings.failure != nil)
        #expect(settings.appearance.snapshot == before)
    }

    /// Replacement requires approval and rejects approval made stale by another window.
    @Test func replacementUsesExactApprovedRevision() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = try makeSettings(fixture)
        let id = UUID()
        settings.importPack(from: try fixture.source(id: id, name: "First"))
        await settings.waitForOperation()
        settings.importPack(from: try fixture.source(id: id, name: "Second"))
        await settings.waitForOperation()
        let approval = try #require(settings.replacement)
        #expect(settings.entries.first?.name == "First")
        settings.replace(approval)
        await settings.waitForOperation()
        #expect(settings.entries.first?.name == "Second")
        settings.replace(approval)
        await settings.waitForOperation()
        #expect(settings.failure != nil)
        #expect(settings.entries.first?.name == "Second")
    }

    /// Removal publishes the committed fallback to both selection scopes.
    @Test func removalUpdatesSelections() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = try makeSettings(fixture)
        settings.importPack(from: try fixture.source())
        await settings.waitForOperation()
        let entry = try #require(settings.entries.first)
        settings.select(entry.id, for: .application)
        await settings.waitForOperation()
        settings.select(entry.id, for: .wallet(UUID()))
        await settings.waitForOperation()
        settings.remove(entry)
        await settings.waitForOperation()
        #expect(settings.entries.isEmpty)
        #expect(settings.appearance.snapshot?.preferences == AppearancePreferences())
    }

    /// Template export prepares a fresh identity and all app-owned default colors.
    @Test func exportsCompleteDefaultTemplate() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = try makeSettings(fixture)
        defer { settings.finishExport() }
        settings.prepareExport()
        await settings.waitForOperation()
        let templateURL = try #require(settings.export?.url)
        let template = try await PackService().read(from: templateURL)
        #expect(template.id != OriginalAppearance.id)
        #expect(template.name == "My Theme")
        let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: templateURL.appendingPathComponent("manifest.json"))) as? [String: Any])
        let tokens = try #require(manifest["tokens"] as? [String: Any])
        let colors = try #require(tokens["colors"] as? [String: [String: Any]])
        #expect(colors.count == 4)
        #expect(colors.values.allSatisfy { $0.count == 7 })
    }

    /// Cancellation while staging never installs a partial theme or reports a user error.
    @Test func cancellationBeforeCommitDoesNotInstall() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let staged = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        defer { release.continuation.finish() }
        let catalog = try ThemeCatalog(directory: fixture.directory, packages: InterceptedPackages {
            staged.continuation.finish()
            for await _ in release.stream {}
            try Task.checkCancellation()
        })
        let settings = AppearanceSettings(appearance: AppearanceCoordinator(store: try AppearanceStore(directory: fixture.directory)),
                                          catalog: catalog, packages: PackService())
        settings.importPack(from: try fixture.source())
        for await _ in staged.stream {}
        #expect(settings.activity != nil)
        settings.cancel()
        release.continuation.finish()
        await settings.waitForOperation()
        #expect(try await catalog.entries().isEmpty)
        #expect(settings.failure == nil)
        #expect(settings.activity == nil)
    }

    /// Closing the initiating window after commit still updates the shared snapshot.
    @Test func cancellationAfterCommitPublishesToOtherWindows() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let committed = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        defer { release.continuation.finish() }
        let catalog = CommittedImportCatalog(base: try ThemeCatalog(directory: fixture.directory)) {
            committed.continuation.finish()
            for await _ in release.stream {}
        }
        let shared = AppearanceCoordinator(store: try AppearanceStore(directory: fixture.directory))
        let settings = AppearanceSettings(appearance: shared, catalog: catalog, packages: PackService())
        settings.importPack(from: try fixture.source(name: "Committed"))
        for await _ in committed.stream {}
        settings.cancel()
        release.continuation.finish()
        await settings.waitForOperation()
        #expect(shared.snapshot?.entries.values.first?.name == "Committed")
        #expect(settings.failure == nil)
    }

    /// A wallet can explicitly keep Original while other wallets follow a custom app default.
    @Test func originalWalletOverrideRemainsIndependent() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let nativeURL = try fixture.source(id: OriginalAppearance.id, name: "Original")
        let bundled = [BundledTheme(id: OriginalAppearance.id, name: "Original", url: nativeURL)]
        let catalog = try ThemeCatalog(directory: fixture.directory, builtIns: bundled)
        let appearance = AppearanceCoordinator(store: try AppearanceStore(directory: fixture.directory, builtIns: bundled))
        let settings = AppearanceSettings(appearance: appearance, catalog: catalog, packages: PackService())
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let wallet = UUID()
        settings.select(entry.id, for: .application)
        await settings.waitForOperation()
        settings.select(OriginalAppearance.id, for: .wallet(wallet))
        await settings.waitForOperation()
        #expect(appearance.snapshot?.theme(for: wallet)?.id == OriginalAppearance.id)
        #expect(appearance.snapshot?.theme(for: UUID())?.id == entry.id)
        settings.select(nil, for: .wallet(wallet))
        await settings.waitForOperation()
        #expect(appearance.snapshot?.theme(for: wallet)?.id == entry.id)
    }

    /// Creates real services against one test's isolated storage.
    /// - Parameter fixture: The owner of this test's temporary directories.
    /// - Returns: An independent presentation coordinator.
    /// - Throws: An invalid test storage configuration.
    private func makeSettings(_ fixture: CatalogFixture) throws -> AppearanceSettings {
        AppearanceSettings(appearance: AppearanceCoordinator(store: try AppearanceStore(directory: fixture.directory)),
                           catalog: try ThemeCatalog(directory: fixture.directory), packages: PackService())
    }
}
