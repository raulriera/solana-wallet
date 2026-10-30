import Foundation
import Themes

/// A theme catalog that stores installed packages in a folder.
nonisolated struct ThemeCatalog: ThemeCatalogProviding {
    private let storage: ThemeStorage
    private let packages: any PackServicing

    /// Creates a catalog.
    ///
    /// - Parameters:
    ///   - directory: The folder that stores installed themes.
    ///   - builtIns: The bundled themes.
    ///   - packages: The service that reads and writes packages.
    init(directory: URL,
         builtIns: [BundledTheme] = [], packages: any PackServicing = PackService()) {
        storage = ThemeStorage(directory: directory, builtIns: builtIns)
        self.packages = packages
    }

    @concurrent
    func entries() async throws -> [ThemeEntry] {
        try await CatalogIO.perform { _ in
            let state = try CatalogFiles.state(in: storage.directory)
            return Array(try state.entries(including: storage.builtInEntries).values)
        }
    }

    @concurrent
    func install(_ pack: Pack, replacing existing: ThemeEntry?) async throws -> ThemeEntry {
        guard storage.builtIns[pack.id] == nil, existing?.origin != .builtIn else {
            throw ThemeCatalogError.builtInTheme
        }
        guard existing == nil || existing?.id == pack.id else { throw ThemeCatalogError.changed }
        let stage = try await CatalogIO.perform { checkCancellation in
            try CatalogFiles.check(pack.id, expected: existing, in: storage.directory)
            try checkCancellation()
            return try CatalogFiles.staging(in: storage.directory)
        }
        do {
            try await packages.save(pack, to: stage.appendingPathComponent(CatalogFiles.packageName))
            let entry = ThemeEntry(id: pack.id, name: pack.name, origin: .custom)
            try await CatalogIO.perform { checkCancellation in
                var state = try CatalogFiles.check(pack.id, expected: existing, in: storage.directory)
                let destination = CatalogFiles.package(for: entry, in: storage.directory)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try checkCancellation()
                try CatalogFiles.move(stage.appendingPathComponent(CatalogFiles.packageName), to: destination)
                do {
                    state.customEntries[entry.id] = entry
                    try CatalogFiles.commit(state, in: storage.directory, checkCancellation: checkCancellation)
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    throw error
                }
            }
            await CatalogIO.discard(stage)
            if let existing { await CatalogIO.discard(CatalogFiles.package(for: existing, in: storage.directory)) }
            return entry
        } catch {
            await CatalogIO.discard(stage)
            throw error
        }
    }

    @concurrent
    func pack(for entry: ThemeEntry) async throws -> Pack {
        let url: URL
        if let bundled = storage.builtIns[entry.id] {
            guard bundled.entry == entry else { throw ThemeCatalogError.changed }
            url = bundled.url
        } else {
            try await CatalogIO.perform { _ -> Void in
                try CatalogFiles.check(entry.id, expected: entry, in: storage.directory)
            }
            url = CatalogFiles.package(for: entry, in: storage.directory)
        }
        let pack = try await packages.read(from: url)
        if entry.origin == .custom {
            try await CatalogIO.perform { _ -> Void in
                try CatalogFiles.check(entry.id, expected: entry, in: storage.directory)
            }
        }
        guard pack.id == entry.id, pack.name == entry.name else { throw ThemeCatalogError.invalidStorage }
        return pack
    }

    @concurrent
    func remove(_ entry: ThemeEntry) async throws {
        guard storage.builtIns[entry.id] == nil, entry.origin == .custom else { throw ThemeCatalogError.builtInTheme }
        try await CatalogIO.perform { checkCancellation in
            var state = try CatalogFiles.check(entry.id, expected: entry, in: storage.directory)
            state.customEntries[entry.id] = nil
            state.preferences.forget(entry.id)
            try CatalogFiles.commit(state, in: storage.directory, checkCancellation: checkCancellation)
        }
        await CatalogIO.discard(CatalogFiles.package(for: entry, in: storage.directory))
    }
}
