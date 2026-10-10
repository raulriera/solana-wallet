import Darwin
import Foundation

/// Private metadata and atomic directory operations, used only inside CatalogIO.
nonisolated enum CatalogFiles {
    static let packageName = "Theme.xtheme"
    static let metadataName = "state.json"

    /// Reads catalog metadata and preferences without touching manifests or assets.
    /// - Parameter directory: The private catalog root.
    /// - Returns: Current committed state, or an empty state before the first mutation.
    /// - Throws: A storage error, including corrupt or mismatched metadata.
    static func state(in directory: URL) throws -> CatalogState {
        let url = directory.appendingPathComponent(metadataName)
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ThemeCatalogError.invalidStorage }
        } catch CocoaError.fileReadNoSuchFile { return CatalogState() }
        let state = try JSONDecoder().decode(CatalogState.self, from: Data(contentsOf: url))
        guard state.customEntries.allSatisfy({ $0.key == $0.value.id && $0.value.origin == .custom }),
              Set(state.customEntries.values.map(\.revision)).count == state.customEntries.count else {
            throw ThemeCatalogError.invalidStorage
        }
        return state
    }

    /// Checks that a mutation still refers to the entry the caller reviewed.
    /// - Parameters:
    ///   - id: The identity being installed, read, or removed.
    ///   - expected: The approved revision, or `nil` when creating a new identity.
    ///   - directory: The private catalog root.
    /// - Returns: The checked state for a subsequent mutation on the same I/O queue.
    /// - Throws: A replacement-required or changed-entry error before any mutation.
    @discardableResult
    static func check(_ id: UUID, expected: ThemeEntry?, in directory: URL) throws -> CatalogState {
        let state = try state(in: directory)
        let current = state.customEntries[id]
        if let current, expected == nil { throw ThemeCatalogError.replacementRequired(current) }
        guard current == expected else { throw ThemeCatalogError.changed }
        return state
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

    /// Commits catalog entries and selections together using an atomic metadata replacement.
    /// - Parameters:
    ///   - state: Updated state read on the same serial I/O queue.
    ///   - directory: The private catalog root.
    ///   - checkCancellation: The final cancellation checkpoint before the atomic write.
    /// - Returns: Committed state with its monotonically increasing revision.
    /// - Throws: An encoding, filesystem, or pre-commit cancellation error.
    @discardableResult
    static func commit(_ state: CatalogState, in directory: URL,
                       checkCancellation: () throws -> Void) throws -> CatalogState {
        var committed = state
        guard committed.revision < UInt64.max else { throw ThemeCatalogError.invalidStorage }
        committed.revision += 1
        let data = try JSONEncoder().encode(committed)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try checkCancellation()
        try data.write(to: directory.appendingPathComponent(metadataName), options: .atomic)
        return committed
    }

    /// Locates immutable package bytes for one installed revision.
    /// - Parameters:
    ///   - entry: A custom catalog entry.
    ///   - directory: The private catalog root.
    /// - Returns: The generation-specific package directory.
    static func package(for entry: ThemeEntry, in directory: URL) -> URL {
        directory.appendingPathComponent("Packages").appendingPathComponent(entry.revision.uuidString + ".xtheme")
    }

    /// Commits a complete directory in one same-volume rename operation.
    ///
    /// Exclusive insertion cannot overwrite another installed generation.
    /// - Parameters:
    ///   - source: The staged package directory.
    ///   - destination: The final location on the same volume.
    /// - Throws: The filesystem error from the atomic operation.
    static func move(_ source: URL, to destination: URL) throws {
        let errorCode = try source.withUnsafeFileSystemRepresentation { sourcePath in
            guard let sourcePath else { throw ThemeCatalogError.invalidStorage }
            return try destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let destinationPath else { throw ThemeCatalogError.invalidStorage }
                let status = renameatx_np(AT_FDCWD, sourcePath, AT_FDCWD, destinationPath,
                                         UInt32(RENAME_EXCL))
                return status == 0 ? 0 : errno
            }
        }
        guard errorCode == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO) }
    }
}
