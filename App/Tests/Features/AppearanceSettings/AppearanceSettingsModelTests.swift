import Foundation
import Observation
import SwiftUI
import Synchronization
import Testing
import Themes
@testable import widgets

@MainActor @Suite(.timeLimit(.minutes(1)))
struct AppearanceSettingsModelTests {
    @Test func `Selection rejects overlapping operations`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = makeSettings(fixture)
        settings.importPack(from: try fixture.source())
        await settings.waitForOperation()
        let entry = try #require(settings.entries.first)
        let before = settings.appearance.snapshot

        settings.select(entry.id)
        #expect(!settings.canStartOperation)
        #expect(settings.appearance.snapshot == before)
        settings.select(nil)
        await settings.waitForOperation()

        #expect(settings.appearance.snapshot?.preferences.themeID == entry.id)
        #expect(settings.error == nil)
        #expect(settings.canStartOperation)
    }

    @Test func `Import installs without selecting`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = makeSettings(fixture)
        try await settings.appearance.activate()
        settings.importPack(from: try fixture.source(name: "Imported"))
        await settings.waitForOperation()
        #expect(settings.error == nil)
        #expect(settings.entries.map(\.name) == ["Imported"])
        #expect(settings.appearance.snapshot?.preferences == AppearancePreferences())
    }

    @Test func `Invalid import preserves selection`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = makeSettings(fixture)
        settings.importPack(from: try fixture.source())
        await settings.waitForOperation()
        let entry = try #require(settings.entries.first)
        settings.select(entry.id)
        await settings.waitForOperation()
        let before = settings.appearance.snapshot
        let invalid = try fixture.source()
        try Data("{}".utf8).write(to: invalid.appendingPathComponent("manifest.json"))
        settings.importPack(from: invalid)
        await settings.waitForOperation()
        #expect(settings.error == .importFailed)
        #expect(settings.appearance.snapshot == before)
    }

    @Test func `Replacement uses exact approved revision`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = makeSettings(fixture)
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

    @Test func `Removal updates selections`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = makeSettings(fixture)
        settings.importPack(from: try fixture.source())
        await settings.waitForOperation()
        let entry = try #require(settings.entries.first)
        settings.select(entry.id)
        await settings.waitForOperation()
        settings.remove(entry)
        await settings.waitForOperation()
        #expect(settings.entries.isEmpty)
        #expect(settings.appearance.snapshot?.preferences == AppearancePreferences())
    }

    @Test func `Exports complete default template`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = makeSettings(fixture)
        defer { settings.finishExport() }
        settings.prepareExport()
        await settings.waitForOperation()
        let templateURL = try #require(settings.export?.url)
        let template = try await PackService().read(from: templateURL)
        #expect(template.id != OriginalAppearance.id)
        #expect(!template.name.isEmpty)
        let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: templateURL.appendingPathComponent("manifest.json"))) as? [String: Any])
        let tokens = try #require(manifest["tokens"] as? [String: Any])
        let colors = try #require(tokens["colors"] as? [String: [String: Any]])
        #expect(colors.count == 4)
        #expect(colors.values.allSatisfy { $0.count == 7 })
    }

    @Test func `Theme Packs opens an export staged before it appeared`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = makeSettings(fixture)
        defer { settings.finishExport() }
        settings.prepareExport()
        await settings.waitForOperation()
        try #require(settings.export != nil)

        let hosted = try HostedWindow(Form { ThemePacksSection(settings: settings) })
        defer { hosted.close() }

        #expect(try await hosted.presentsViewController())
    }

    @Test func `Cancellation before commit does not install`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let staged = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        defer { release.continuation.finish() }
        let catalog = ThemeCatalog(directory: fixture.directory, packages: InterceptedPackages {
            staged.continuation.finish()
            for await _ in release.stream {}
            try Task.checkCancellation()
        })
        let settings = AppearanceSettingsModel(appearance: AppearanceCoordinator(store: AppearanceStore(directory: fixture.directory), recovery: nil),
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

    @Test func `Cancellation after commit publishes to other windows`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let committed = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        defer { release.continuation.finish() }
        let catalog = CommittedImportCatalog(base: ThemeCatalog(directory: fixture.directory)) {
            committed.continuation.finish()
            for await _ in release.stream {}
        }
        let shared = AppearanceCoordinator(store: AppearanceStore(directory: fixture.directory), recovery: nil)
        let settings = AppearanceSettingsModel(appearance: shared, catalog: catalog, packages: PackService())
        settings.importPack(from: try fixture.source(name: "Committed"))
        for await _ in committed.stream {}
        settings.cancel()
        release.continuation.finish()
        await settings.waitForOperation()
        #expect(shared.snapshot?.entries.values.first?.name == "Committed")
        #expect(settings.error == nil)
    }

    @Test(arguments: [false, true])
    func `Cancellation only notifies when replacement changes`(hasPendingReplacement: Bool) async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = makeSettings(fixture)
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

    @Test(arguments: [false, true])
    func `Replacement notification follows imported contents`(changesColors: Bool) async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let settings = makeSettings(fixture)
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
        let settings = makeSettings(fixture)

        settings.report(error, defaultingTo: .exportFailed)

        #expect(settings.error == expected)
    }

    private func makeSettings(_ fixture: CatalogFixture) -> AppearanceSettingsModel {
        AppearanceSettingsModel(
            appearance: AppearanceCoordinator(store: AppearanceStore(directory: fixture.directory), recovery: nil),
            catalog: ThemeCatalog(directory: fixture.directory), packages: PackService()
        )
    }
}
