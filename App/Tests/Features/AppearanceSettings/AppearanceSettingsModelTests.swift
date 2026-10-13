import Foundation
import Observation
import SwiftUI
import Synchronization
import Testing
import Themes
@testable import widgets

@MainActor @Suite(.timeLimit(.minutes(1)))
struct AppearanceSettingsModelTests {
    /// Selection keeps committed state visible and rejects overlapping writes until persistence completes.
    @Test func `Selection rejects overlapping operations`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = try makeSettings(fixture)
        settings.importPack(from: try fixture.source())
        await settings.waitForOperation()
        let entry = try #require(settings.entries.first)
        let before = settings.appearance.snapshot

        settings.select(entry.id, for: .application)
        #expect(!settings.canStartOperation)
        #expect(settings.appearance.snapshot == before)
        settings.select(nil, for: .application)
        await settings.waitForOperation()

        #expect(settings.appearance.snapshot?.preferences.appThemeID == entry.id)
        #expect(settings.error == nil)
        #expect(settings.canStartOperation)
    }

    /// Import updates shared metadata without changing the app or wallet selection.
    @Test func `Import installs without selecting`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = try makeSettings(fixture)
        try await settings.appearance.activate()
        settings.importPack(from: try fixture.source(name: "Imported"))
        await settings.waitForOperation()
        #expect(settings.error == nil)
        #expect(settings.entries.map(\.name) == ["Imported"])
        #expect(settings.appearance.snapshot?.preferences == AppearancePreferences())
    }

    /// A failed import preserves every installed entry and its selected appearance.
    @Test func `Invalid import preserves selection`() async throws {
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
        #expect(settings.error == .importFailed)
        #expect(settings.appearance.snapshot == before)
    }

    /// Replacement requires approval and rejects approval made stale by another window.
    @Test func `Replacement uses exact approved revision`() async throws {
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
        #expect(settings.error == .changedElsewhere)
        #expect(settings.entries.first?.name == "Second")
    }

    /// Removal publishes the committed fallback to both selection scopes.
    @Test func `Removal updates selections`() async throws {
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
    @Test func `Exports complete default template`() async throws {
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

    /// An export staged while Theme Packs was off screen opens when the section appears, instead of locking theme actions.
    @Test func `Theme Packs opens an export staged before it appeared`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = try makeSettings(fixture)
        defer { settings.finishExport() }
        settings.prepareExport()
        await settings.waitForOperation()
        try #require(settings.export != nil)

        let hosted = try HostedWindow(Form { ThemePacksSection(settings: settings) })
        defer { hosted.close() }

        #expect(try await hosted.presentsViewController())
    }

    /// Cancellation while staging never installs a partial theme or reports a user error.
    @Test func `Cancellation before commit does not install`() async throws {
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
        let settings = AppearanceSettingsModel(appearance: AppearanceCoordinator(store: try AppearanceStore(directory: fixture.directory)),
                                               catalog: catalog, packages: PackService())
        settings.importPack(from: try fixture.source())
        for await _ in staged.stream {}
        #expect(!settings.canStartOperation)
        settings.cancel()
        release.continuation.finish()
        await settings.waitForOperation()
        #expect(try await catalog.entries().isEmpty)
        #expect(settings.error == nil)
        #expect(settings.canStartOperation)
    }

    /// Closing the initiating window after commit still updates the shared snapshot.
    @Test func `Cancellation after commit publishes to other windows`() async throws {
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
        let settings = AppearanceSettingsModel(appearance: shared, catalog: catalog, packages: PackService())
        settings.importPack(from: try fixture.source(name: "Committed"))
        for await _ in committed.stream {}
        settings.cancel()
        release.continuation.finish()
        await settings.waitForOperation()
        #expect(shared.snapshot?.entries.values.first?.name == "Committed")
        #expect(settings.error == nil)
    }

    /// A wallet can explicitly keep Original while other wallets follow a custom app default.
    @Test func `Original wallet override remains independent`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let nativeURL = try fixture.source(id: OriginalAppearance.id, name: "Original")
        let bundled = [BundledTheme(id: OriginalAppearance.id, name: "Original", url: nativeURL)]
        let catalog = try ThemeCatalog(directory: fixture.directory, builtIns: bundled)
        let appearance = AppearanceCoordinator(store: try AppearanceStore(directory: fixture.directory, builtIns: bundled))
        let settings = AppearanceSettingsModel(appearance: appearance, catalog: catalog, packages: PackService())
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

    /// Cancelling notifies replacement observers only when there is an approval to dismiss.
    /// - Parameter hasPendingReplacement: Whether cancellation clears an existing approval.
    /// - Throws: A fixture or package-reading error.
    @Test(arguments: [false, true])
    func `Cancellation only notifies when replacement changes`(hasPendingReplacement: Bool) async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = try makeSettings(fixture)
        if hasPendingReplacement {
            let pack = try await PackService().read(from: fixture.source())
            settings.replacement = AppearanceSettingsModel.Replacement(
                pack: pack, existing: ThemeEntry(id: pack.id, name: pack.name, origin: .custom)
            )
        }
        let changed = Mutex(false)
        withObservationTracking {
            _ = settings.replacement
        } onChange: {
            changed.withLock { $0 = true }
        }

        settings.cancel()

        let notified = changed.withLock(\.self)
        #expect(notified == hasPendingReplacement)
        #expect(settings.replacement == nil)
    }

    /// Equal imported contents do not notify, but changed colors under the same identity do.
    /// - Parameter changesColors: Whether the second import changes a color override.
    /// - Throws: A fixture, parsing, or package-reading error.
    @Test(arguments: [false, true])
    func `Replacement notification follows imported contents`(changesColors: Bool) async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = try makeSettings(fixture)
        let source = try fixture.source()
        let first = try await PackService().read(from: source)
        let existing = ThemeEntry(id: first.id, name: first.name, origin: .custom)
        settings.replacement = AppearanceSettingsModel.Replacement(pack: first, existing: existing)
        if changesColors {
            let url = source.appendingPathComponent("manifest.json")
            var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            manifest["tokens"] = ["colors": ["light": ["accent": ["srgb": "#123456"]]]]
            try JSONSerialization.data(withJSONObject: manifest).write(to: url)
        }
        let second = try await PackService().read(from: source)
        let changed = Mutex(false)
        withObservationTracking {
            _ = settings.replacement
        } onChange: {
            changed.withLock { $0 = true }
        }

        settings.replacement = AppearanceSettingsModel.Replacement(pack: second, existing: existing)

        let notified = changed.withLock(\.self)
        #expect(notified == changesColors)
    }

    /// Catalog conflicts explain their cause, other failures show the failed action's error, and cancellation is silent.
    /// - Parameters:
    ///   - error: A service or file dialog error.
    ///   - expected: The error the alert explains, or `nil` when no alert shows.
    /// - Throws: An invalid test storage configuration.
    @Test(arguments: [
        (ThemeCatalogError.builtInTheme as any Error, ThemeError.builtInTheme as ThemeError?),
        (ThemeCatalogError.changed, .changedElsewhere),
        (CocoaError(.fileWriteUnknown), .exportFailed),
        (CocoaError(.userCancelled), nil),
        (CancellationError(), nil),
    ])
    func `Failures map to the alert's explanation`(error: any Error, expected: ThemeError?) throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = try makeSettings(fixture)

        settings.report(error, defaultingTo: .exportFailed)

        #expect(settings.error == expected)
    }

    /// Creates real services against one test's isolated storage.
    /// - Parameter fixture: The owner of this test's temporary directories.
    /// - Returns: An appearance settings model with its own window state.
    /// - Throws: An invalid test storage configuration.
    private func makeSettings(_ fixture: CatalogFixture) throws -> AppearanceSettingsModel {
        AppearanceSettingsModel(
            appearance: AppearanceCoordinator(store: try AppearanceStore(directory: fixture.directory)),
            catalog: try ThemeCatalog(directory: fixture.directory), packages: PackService()
        )
    }
}
