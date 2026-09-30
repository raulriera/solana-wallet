import Darwin
import Foundation

/// Private metadata and atomic directory operations, used only inside CatalogIO.
nonisolated enum CatalogFiles {
    static let packageName = "Theme.xtheme"
    private static let metadataName = "entry.json"

    /// Reads one catalog entry without touching the package's manifest or assets.
    /// - Parameters:
    ///   - id: The expected package identity.
    ///   - directory: The private catalog root.
    /// - Returns: The current custom revision, or `nil` when absent.
    /// - Throws: A storage error, including corrupt or mismatched metadata.
    static func entry(_ id: UUID, in directory: URL) throws -> ThemeEntry? {
        let folder = directory.appendingPathComponent(id.uuidString)
        do {
            let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw ThemeCatalog.Failure.invalidStorage }
        } catch CocoaError.fileReadNoSuchFile { return nil }
        let data = try Data(contentsOf: folder.appendingPathComponent(metadataName))
        let entry = try JSONDecoder().decode(ThemeEntry.self, from: data)
        guard entry.id == id, entry.origin == .custom else { throw ThemeCatalog.Failure.invalidStorage }
        return entry
    }

    /// Checks that a mutation still refers to the entry the caller reviewed.
    /// - Parameters:
    ///   - id: The identity being installed, read, or removed.
    ///   - expected: The approved revision, or `nil` when creating a new identity.
    ///   - directory: The private catalog root.
    /// - Throws: A replacement-required or changed-entry error before any mutation.
    static func check(_ id: UUID, expected: ThemeEntry?, in directory: URL) throws {
        let current = try entry(id, in: directory)
        if let current, expected == nil { throw ThemeCatalog.Failure.replacementRequired(current) }
        guard current == expected else { throw ThemeCatalog.Failure.changed }
    }

    /// Creates operation-local staging on the catalog's volume.
    /// - Parameter directory: The private catalog root, created when necessary.
    /// - Returns: An OS-managed temporary directory on the same volume.
    /// - Throws: A filesystem error.
    static func staging(in directory: URL) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        return try manager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                               appropriateFor: directory, create: true)
    }

    /// Writes metadata beside a staged package before it becomes visible to readers.
    /// - Parameters:
    ///   - entry: The new custom revision.
    ///   - directory: The operation's uncommitted staging directory.
    /// - Throws: An encoding or filesystem error.
    static func write(_ entry: ThemeEntry, in directory: URL) throws {
        try JSONEncoder().encode(entry).write(to: directory.appendingPathComponent(metadataName), options: .atomic)
    }

    /// Commits a complete directory in one same-volume rename operation.
    ///
    /// Exclusive insertion cannot overwrite a competing import. Replacement swaps
    /// directories atomically, leaving the old contents in staging for later cleanup.
    /// A failed rename leaves the installed directory unchanged.
    /// - Parameters:
    ///   - source: The staged directory or entry being removed.
    ///   - destination: The final location on the same volume.
    ///   - replacing: Whether to exchange two existing directories instead of inserting exclusively.
    /// - Throws: The filesystem error from the atomic operation.
    static func move(_ source: URL, to destination: URL, replacing: Bool = false) throws {
        let failure = try source.withUnsafeFileSystemRepresentation { sourcePath in
            guard let sourcePath else { throw ThemeCatalog.Failure.invalidStorage }
            return try destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let destinationPath else { throw ThemeCatalog.Failure.invalidStorage }
                let status = renameatx_np(AT_FDCWD, sourcePath, AT_FDCWD, destinationPath,
                                         UInt32(replacing ? RENAME_SWAP : RENAME_EXCL))
                return status == 0 ? 0 : errno
            }
        }
        guard failure == 0 else { throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO) }
    }
}
