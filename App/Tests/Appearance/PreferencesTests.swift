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
        #expect(snapshot.theme(for: UUID()) == nil)
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

    @Test func `Wallet overrides persist and clear back to application default`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let a = try await catalog.install(PackService().read(from: fixture.source()))
        let b = try await catalog.install(PackService().read(from: fixture.source()))
        let store = AppearanceStore(directory: fixture.directory)
        let wallet = UUID()
        _ = try await store.select(a.id, for: .application)
        _ = try await store.select(a.id, for: .wallet(wallet))
        _ = try await store.select(b.id, for: .application)
        let reopened = AppearanceStore(directory: fixture.directory)
        let saved = try await reopened.load()
        #expect(saved.theme(for: wallet) == a)
        #expect(saved.theme(for: UUID()) == b)
        #expect(saved.theme(for: nil) == b)
        let cleared = try await reopened.select(nil, for: .wallet(wallet))
        #expect(cleared.theme(for: wallet) == b)
        #expect(cleared.preferences.walletThemeIDs[wallet] == nil)
    }

    @Test func `Concurrent wallet edits do not overwrite each other`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let wallets = (0..<20).map { _ in UUID() }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for wallet in wallets {
                group.addTask {
                    let store = AppearanceStore(directory: fixture.directory)
                    _ = try await store.select(entry.id, for: .wallet(wallet))
                }
            }
            try await group.waitForAll()
        }
        let saved = try await AppearanceStore(directory: fixture.directory).load()
        #expect(saved.preferences.walletThemeIDs == Dictionary(uniqueKeysWithValues: wallets.map { ($0, entry.id) }))
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
        let selected = try await store.select(entry.id, for: .application)
        release.continuation.finish()
        let imported = try await importing.value
        let current = try await store.load()
        #expect(current.preferences == selected.preferences)
        #expect(current.entries[imported.id] == imported)
        #expect(current.theme(for: nil) == entry)
    }

    @Test(arguments: [false, true]) func `Deleting theme commits selection fallbacks`(selectedAsDefault: Bool) async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let pack = try await PackService().read(from: fixture.source())
        let removed = try await catalog.install(pack)
        let kept = try await catalog.install(PackService().read(from: fixture.source()))
        let store = AppearanceStore(directory: fixture.directory)
        let wallet = UUID(), otherWallet = UUID()
        _ = try await store.select(selectedAsDefault ? removed.id : kept.id, for: .application)
        _ = try await store.select(removed.id, for: .wallet(wallet))
        _ = try await store.select(kept.id, for: .wallet(otherWallet))
        let before = try await store.load()
        try await catalog.remove(removed)
        let after = try await store.load()
        #expect(after.revision == before.revision + 1)
        #expect(after.theme(for: wallet) == (selectedAsDefault ? nil : kept))
        #expect(after.theme(for: otherWallet) == kept)
        #expect(after.preferences.walletThemeIDs[wallet] == nil)
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
        let selected = try await store.select(old.id, for: .application)
        let updated = try await catalog.install(pack, replacing: old)
        let loaded = try await store.load()
        #expect(loaded.preferences == selected.preferences)
        #expect(loaded.theme(for: nil) == updated)
        #expect(loaded.revision > selected.revision)
        #expect(loaded.orderedEntryIDs == selected.orderedEntryIDs)
    }

    @Test func `Forgetting a theme clears only its selections`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let forgotten = try await catalog.install(PackService().read(from: fixture.source()))
        let kept = try await catalog.install(PackService().read(from: fixture.source()))
        let store = AppearanceStore(directory: fixture.directory)
        let (wallet, other) = (UUID(), UUID())
        _ = try await store.select(forgotten.id, for: .application)
        _ = try await store.select(forgotten.id, for: .wallet(wallet))
        _ = try await store.select(kept.id, for: .wallet(other))

        let snapshot = try await store.forget(forgotten.id)

        #expect(snapshot.theme(for: nil) == nil)
        #expect(snapshot.theme(for: wallet) == nil)
        #expect(snapshot.theme(for: other) == kept)
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
        let selected = try await store.select(builtIn.entry.id, for: .application)
        _ = try await store.select(custom.id, for: .wallet(UUID()))
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
        let before = try await store.select(entry.id, for: .application)
        await #expect(throws: ThemeCatalogError.changed) { try await store.select(UUID(), for: .application) }
        #expect(try await store.load() == before)
    }

    @Test func `Failed deletion preserves catalog and selections`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let store = AppearanceStore(directory: fixture.directory)
        let before = try await store.select(entry.id, for: .application)
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
        let before = try await store.select(entry.id, for: .application)
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
        let before = try await store.select(entry.id, for: .application)
        let metadata = fixture.directory.appendingPathComponent(CatalogFiles.metadataName)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fixture.directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.directory.path) }
        let data = try Data(contentsOf: metadata)
        #expect(try await store.select(entry.id, for: .application) == before)
        #expect(try Data(contentsOf: metadata) == data)
    }

    @Test func `Unreadable metadata resets selections`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let catalog = ThemeCatalog(directory: fixture.directory)
        let entry = try await catalog.install(PackService().read(from: fixture.source()))
        let store = AppearanceStore(directory: fixture.directory)
        _ = try await store.select(entry.id, for: .application)
        try Data("invalid".utf8).write(to: fixture.directory.appendingPathComponent(CatalogFiles.metadataName))

        #expect(try await store.load().preferences == AppearancePreferences())
        #expect(try await store.reset().preferences == AppearancePreferences())
    }

    @Test func `Missing built-in selections reconcile to original appearance`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let builtIn = BundledTheme(id: UUID(), name: "Bundled", url: fixture.root)
        let old = AppearanceStore(directory: fixture.directory, builtIns: [builtIn])
        _ = try await old.select(builtIn.entry.id, for: .application)
        let before = try await old.select(builtIn.entry.id, for: .wallet(UUID()))
        let current = AppearanceStore(directory: fixture.directory)
        let reconciled = try await current.load()
        #expect(reconciled.preferences == AppearancePreferences())
        #expect(reconciled.revision == before.revision + 1)
        #expect(try await current.load() == reconciled)
    }
}
