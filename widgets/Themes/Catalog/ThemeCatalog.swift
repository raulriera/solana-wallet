import Foundation
import Themes

/// App-owned installed packages with immutable built-ins and explicit custom replacement.
nonisolated struct ThemeCatalog: ThemeCatalogProviding {
    /// A catalog operation cannot proceed with the supplied identity or revision.
    enum Failure: Error, Sendable, Equatable {
        case builtInTheme
        case replacementRequired(ThemeEntry)
        case changed
        case invalidStorage
        case duplicateBuiltIn
    }

    private let directory: URL
    private let builtIns: [UUID: BundledTheme]
    private let packages: any PackServicing

    /// Creates shared catalog access without loading any packages or image data.
    /// - Parameters:
    ///   - directory: App-private persistent storage; defaults to Application Support.
    ///   - builtIns: Immutable bundled themes supplied by app composition.
    ///   - packages: The framework service owning package validation and serialization.
    /// - Throws: A configuration error for duplicate built-in identities or a non-file location.
    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("Themes"),
         builtIns: [BundledTheme] = [], packages: any PackServicing = PackService()) throws {
        guard directory.isFileURL else { throw Failure.invalidStorage }
        guard Set(builtIns.map(\.entry.id)).count == builtIns.count else { throw Failure.duplicateBuiltIn }
        self.directory = directory
        self.builtIns = Dictionary(uniqueKeysWithValues: builtIns.map { ($0.entry.id, $0) })
        self.packages = packages
    }

    /// Reads catalog metadata without loading installed packages.
    /// - Returns: All custom and bundled entries, without imposing UI ordering.
    /// - Throws: A storage or cancellation error; corrupt entries are not silently omitted.
    @concurrent
    func entries() async throws -> [ThemeEntry] {
        try await CatalogIO.perform { checkCancellation in
            var result = builtIns.values.map(\.entry)
            let folders: [URL]
            do {
                folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            } catch CocoaError.fileReadNoSuchFile { return result }
            for folder in folders {
                try checkCancellation()
                guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
                guard builtIns[id] == nil, let entry = try CatalogFiles.entry(id, in: directory) else {
                    throw Failure.invalidStorage
                }
                result.append(entry)
            }
            return result
        }
    }

    /// Installs one validated snapshot while preserving its omitted settings.
    /// - Parameters:
    ///   - pack: Independently owned package bytes from the framework's reader.
    ///   - existing: The exact custom revision approved for replacement, or `nil` for insertion.
    /// - Returns: The committed entry without changing any appearance preference.
    /// - Throws: A conflict, immutable-theme, storage, or pre-commit cancellation error.
    @concurrent
    func install(_ pack: Pack, replacing existing: ThemeEntry?) async throws -> ThemeEntry {
        guard builtIns[pack.id] == nil, existing?.origin != .builtIn else { throw Failure.builtInTheme }
        guard existing == nil || existing?.id == pack.id else { throw Failure.changed }
        let stage = try await CatalogIO.perform { checkCancellation in
            try CatalogFiles.check(pack.id, expected: existing, in: directory)
            try checkCancellation()
            return try CatalogFiles.staging(in: directory)
        }
        do {
            try await packages.save(pack, to: stage.appendingPathComponent(CatalogFiles.packageName))
            let entry = ThemeEntry(id: pack.id, name: pack.name, origin: .custom)
            try await CatalogIO.perform { checkCancellation in
                try CatalogFiles.write(entry, in: stage)
                try CatalogFiles.check(pack.id, expected: existing, in: directory)
                try checkCancellation()
                try CatalogFiles.move(stage, to: directory.appendingPathComponent(pack.id.uuidString),
                                      replacing: existing != nil)
            }
            await CatalogIO.discard(stage)
            return entry
        } catch {
            await CatalogIO.discard(stage)
            throw error
        }
    }

    /// Loads only the selected package and rejects a revision replaced during the read.
    /// - Parameter entry: The revision being selected or exported.
    /// - Returns: A validated snapshot with independent image bytes.
    /// - Throws: A changed-entry, package-validation, storage, or cancellation error.
    @concurrent
    func pack(for entry: ThemeEntry) async throws -> Pack {
        let url: URL
        if let bundled = builtIns[entry.id] {
            guard bundled.entry == entry else { throw Failure.changed }
            url = bundled.url
        } else {
            try await CatalogIO.perform { _ in
                try CatalogFiles.check(entry.id, expected: entry, in: directory)
            }
            url = directory.appendingPathComponent(entry.id.uuidString).appendingPathComponent(CatalogFiles.packageName)
        }
        let pack = try await packages.read(from: url)
        if entry.origin == .custom {
            try await CatalogIO.perform { _ in
                try CatalogFiles.check(entry.id, expected: entry, in: directory)
            }
        }
        guard pack.id == entry.id, pack.name == entry.name else { throw Failure.invalidStorage }
        return pack
    }

    /// Removes a custom revision atomically before reclaiming its temporary files.
    /// - Parameter entry: The exact custom entry selected for removal.
    /// - Throws: An immutable-theme, changed-entry, storage, or pre-commit cancellation error.
    @concurrent
    func remove(_ entry: ThemeEntry) async throws {
        guard builtIns[entry.id] == nil, entry.origin == .custom else { throw Failure.builtInTheme }
        let stage = try await CatalogIO.perform { checkCancellation in
            try CatalogFiles.check(entry.id, expected: entry, in: directory)
            let stage = try CatalogFiles.staging(in: directory)
            do {
                try checkCancellation()
                try CatalogFiles.move(directory.appendingPathComponent(entry.id.uuidString),
                                      to: stage.appendingPathComponent("Removed"))
                return stage
            } catch {
                try? FileManager.default.removeItem(at: stage)
                throw error
            }
        }
        await CatalogIO.discard(stage)
    }
}
