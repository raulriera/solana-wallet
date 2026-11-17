import Foundation
import Testing
import Themes
@testable import widgets

@Suite(.timeLimit(.minutes(1)))
nonisolated struct PreferencesTests {
    @Test func `New preferences use original appearance`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let snapshot = try await AppearanceStore(directory: fixture.directory).load()
        #expect(snapshot.preferences == AppearancePreferences())
        #expect(snapshot.theme == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    @Test func `Catalog changes refresh prepared lists`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let builtIn = BundledTheme(id: UUID(), name: "Original", url: fixture.root)
        let catalog = ThemeCatalog(directory: fixture.directory, builtIns: [builtIn])
        let store = AppearanceStore(directory: fixture.directory, builtIns: [builtIn])
        let z = try await catalog.install(PackService().read(from: fixture.source(name: "Zinc")))
        let a = try await catalog.install(PackService().read(from: fixture.source(name: "Amber")))

        let imported = try await store.load()
        #expect(imported.orderedEntries == [builtIn.entry, a, z])
        #expect(imported.orderedEntryIDs == [builtIn.entry.id, a.id, z.id])

        let renamed = try await catalog.install(
            PackService().read(from: fixture.source(id: z.id, name: "Aardvark")), replacing: z
        )
        let replaced = try await store.load()
        #expect(replaced.orderedEntries == [builtIn.entry, renamed, a])
        #expect(replaced.orderedEntryIDs == [builtIn.entry.id, z.id, a.id])

        try await catalog.remove(a)
        let removed = try await store.load()
        #expect(removed.orderedEntries == [builtIn.entry, renamed])
        #expect(removed.orderedEntryIDs == [builtIn.entry.id, z.id])
    }

    @Test func `The app theme persists and clears back to original appearance`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let a = try await catalog.install(PackService().read(from: fixture.source()))
        let b = try await catalog.install(PackService().read(from: fixture.source()))
        let store = AppearanceStore(directory: fixture.directory)
        _ = try await store.select(a.id)
        _ = try await store.select(b.id)
        let reopened = AppearanceStore(directory: fixture.directory)
        let saved = try await reopened.load()
        #expect(saved.theme == b)
        let cleared = try await reopened.select(nil)
        #expect(cleared.theme == nil)
        #expect(cleared.preferences == AppearancePreferences())
    }

    @Test func `The token layout persists apart from the theme and resets to cards`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let store = AppearanceStore(directory: fixture.directory)
        _ = try await store.select(entry.id)
        let selected = try await store.select(.rows)
        #expect(selected.theme == entry)
        let reopened = AppearanceStore(directory: fixture.directory)
        #expect(try await reopened.load() == selected)
        let forgotten = try await reopened.forget(entry.id)
        #expect(forgotten.theme == nil)
        #expect(forgotten.preferences.tokenLayout == .rows)
        let reset = try await reopened.reset()
        #expect(reset.preferences.tokenLayout == .cards)
    }

    @Test func `Preference edits during import survive catalog commit`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let pack = try await PackService().read(from: fixture.source())
        let staged = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        defer { release.continuation.finish() }
        let paused = ThemeCatalog(directory: fixture.directory, packages: InterceptedPackages {
            staged.continuation.finish()
            for await _ in release.stream {}
        })
        let importing = Task { @concurrent in try await paused.install(pack) }
        defer { importing.cancel() }
        for await _ in staged.stream {}
        let store = AppearanceStore(directory: fixture.directory)
        let selected = try await store.select(entry.id)
        release.continuation.finish()
        let imported = try await importing.value
        let current = try await store.load()
        #expect(current.preferences == selected.preferences)
        #expect(current.entries[imported.id] == imported)
        #expect(current.theme == entry)
    }

    @Test(arguments: [false, true]) func `Deleting theme commits selection fallbacks`(selectedAsDefault: Bool) async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let pack = try await PackService().read(from: fixture.source())
        let removed = try await catalog.install(pack)
        let kept = try await catalog.install(PackService().read(from: fixture.source()))
        let store = AppearanceStore(directory: fixture.directory)
        _ = try await store.select(selectedAsDefault ? removed.id : kept.id)
        let before = try await store.load()
        try await catalog.remove(removed)
        let after = try await store.load()
        #expect(after.revision == before.revision + 1)
        #expect(after.theme == (selectedAsDefault ? nil : kept))
        #expect(after.entries[removed.id] == nil)
        _ = try await catalog.install(pack)
        #expect(try await store.load().preferences == after.preferences)
    }

    @Test func `Replacement preserves selections`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let pack = try await PackService().read(from: fixture.source())
        let old = try await catalog.install(pack)
        let store = AppearanceStore(directory: fixture.directory)
        let selected = try await store.select(old.id)
        let updated = try await catalog.install(pack, replacing: old)
        let loaded = try await store.load()
        #expect(loaded.preferences == selected.preferences)
        #expect(loaded.theme == updated)
        #expect(loaded.revision > selected.revision)
        #expect(loaded.orderedEntryIDs == selected.orderedEntryIDs)
    }

    @Test(arguments: [false, true]) func `Forgetting a theme clears only its selection`(isSelected: Bool) async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let forgotten = try await catalog.install(PackService().read(from: fixture.source()))
        let kept = try await catalog.install(PackService().read(from: fixture.source()))
        let store = AppearanceStore(directory: fixture.directory)
        _ = try await store.select(isSelected ? forgotten.id : kept.id)

        let snapshot = try await store.forget(forgotten.id)

        #expect(snapshot.theme == (isSelected ? nil : kept))
        #expect(snapshot.entries[forgotten.id] == forgotten)
        #expect(try await store.load() == snapshot)
    }

    @Test func `Reset clears every selection and preserves installed themes`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let builtIn = BundledTheme(id: UUID(), name: "Bundled", url: fixture.root.appendingPathComponent("Unread"))
        let catalog = ThemeCatalog(directory: fixture.directory, builtIns: [builtIn])
        let custom = try await catalog.install(PackService().read(from: fixture.source()))
        let store = AppearanceStore(directory: fixture.directory, builtIns: [builtIn])
        let selected = try await store.select(custom.id)
        let reset = try await store.reset()
        #expect(reset.preferences == AppearancePreferences())
        #expect(Set(reset.entries.keys) == [builtIn.entry.id, custom.id])
        #expect(reset.orderedEntryIDs == selected.orderedEntryIDs)
        #expect(try await catalog.pack(for: custom).id == custom.id)
        #expect(try await store.load() == reset)
    }

    @Test func `Unavailable selection leaves preferences unchanged`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let store = AppearanceStore(directory: fixture.directory)
        let before = try await store.select(entry.id)
        await #expect(throws: ThemeCatalogError.changed) { try await store.select(UUID()) }
        #expect(try await store.load() == before)
    }

    @Test func `Failed deletion preserves catalog and selections`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let store = AppearanceStore(directory: fixture.directory)
        let before = try await store.select(entry.id)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fixture.directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.directory.path) }
        await #expect(throws: (any Error).self) { try await catalog.remove(entry) }
        #expect(try await store.load() == before)
        #expect(try await catalog.pack(for: entry).id == entry.id)
    }

    @Test func `Failed replacement commit preserves selected package`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let pack = try await PackService().read(from: fixture.source())
        let entry = try await catalog.install(pack)
        let store = AppearanceStore(directory: fixture.directory)
        let before = try await store.select(entry.id)
        let replacement = try await PackService().read(from: fixture.source(id: pack.id, name: "Replacement"))
        let failing = ThemeCatalog(directory: fixture.directory, packages: InterceptedPackages {
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fixture.directory.path)
        })
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.directory.path) }
        await #expect(throws: (any Error).self) { try await failing.install(replacement, replacing: entry) }
        #expect(try await store.load() == before)
        #expect(try await catalog.pack(for: entry).name == pack.name)
        let generations = try FileManager.default.contentsOfDirectory(at: fixture.directory.appendingPathComponent("Packages"),
                                                                      includingPropertiesForKeys: nil)
        #expect(generations == [CatalogFiles.package(for: entry, in: fixture.directory)])
    }

    @Test func `Unchanged preferences keep their revision`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let store = AppearanceStore(directory: fixture.directory)
        let before = try await store.select(entry.id)
        let metadata = fixture.directory.appendingPathComponent(CatalogFiles.metadataName)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fixture.directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.directory.path) }
        let data = try Data(contentsOf: metadata)
        #expect(try await store.select(entry.id) == before)
        #expect(try Data(contentsOf: metadata) == data)
    }

    @Test func `Missing built-in selections reconcile to original appearance`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let builtIn = BundledTheme(id: UUID(), name: "Bundled", url: fixture.root)
        let old = AppearanceStore(directory: fixture.directory, builtIns: [builtIn])
        let before = try await old.select(builtIn.entry.id)
        let current = AppearanceStore(directory: fixture.directory)
        let reconciled = try await current.load()
        #expect(reconciled.preferences == AppearancePreferences())
        #expect(reconciled.revision == before.revision + 1)
        #expect(try await current.load() == reconciled)
    }
}
