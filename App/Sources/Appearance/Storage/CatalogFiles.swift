import Darwin
import Foundation
import Storage

/// File operations on the theme catalog's folder.
nonisolated enum CatalogFiles {
    static let packageName = "Theme.xtheme"
    static let metadataName = "state.json"
    static let coding = VersionedJSONCoding<CatalogState>(version: 1, unusable: .unreadable)

    /// Reads the catalog's state, deleting it and the installed packages when it's unreadable.
    ///
    /// - Parameter directory: The catalog's folder.
    /// - Returns: The saved state, or an empty state when there's none.
    /// - Throws: A storage error.
    static func state(in directory: URL) throws -> CatalogState {
        let url = directory.appendingPathComponent(metadataName)
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ThemeCatalogError.invalidStorage }
        } catch CocoaError.fileReadNoSuchFile { return CatalogState() }
        let data = try Data(contentsOf: url)
        guard let state = coding.decode(data),
              state.customEntries.allSatisfy({ $0.key == $0.value.id && $0.value.origin == .custom }),
              Set(state.customEntries.values.map(\.revision)).count == state.customEntries.count else {
            try discard(packagesIn: directory)
            try FileManager.default.removeItem(at: url)
            return CatalogState()
        }
        return state
    }

    /// Checks that the installed theme with an identity matches the expected entry.
    ///
    /// - Parameters:
    ///   - id: The theme's identity.
    ///   - expected: The expected entry, or `nil` when the theme shouldn't be installed.
    ///   - directory: The catalog's folder.
    /// - Returns: The catalog's state.
    /// - Throws: A replacement-required or changed-entry error.
    @discardableResult
    static func check(_ id: UUID, expected: ThemeEntry?, in directory: URL) throws -> CatalogState {
        let state = try state(in: directory)
        let current = state.customEntries[id]
        if let current, expected == nil { throw ThemeCatalogError.replacementRequired(current) }
        guard current == expected else { throw ThemeCatalogError.changed }
        return state
    }

    /// Creates a temporary folder on the catalog's volume.
    ///
    /// - Parameter directory: The catalog's folder.
    /// - Returns: The temporary folder.
    /// - Throws: A file system error.
    static func staging(in directory: URL) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        return try manager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                               appropriateFor: directory, create: true)
    }

    /// Saves the catalog's state with the next revision in one atomic write.
    ///
    /// - Parameters:
    ///   - state: The state to save.
    ///   - directory: The catalog's folder.
    ///   - checkCancellation: A check that throws when the operation is cancelled.
    /// - Returns: The saved state.
    /// - Throws: An encoding, file system, or cancellation error.
    @discardableResult
    static func commit(_ state: CatalogState, in directory: URL,
                       checkCancellation: () throws -> Void) throws -> CatalogState {
        var committed = state
        guard committed.revision < UInt64.max else { throw ThemeCatalogError.invalidStorage }
        committed.revision += 1
        let data = try coding.encode(committed)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try checkCancellation()
        try data.write(to: directory.appendingPathComponent(metadataName), options: .atomic)
        return committed
    }

    /// Deletes every installed package.
    ///
    /// - Parameter directory: The catalog's folder.
    /// - Throws: A file system error.
    private static func discard(packagesIn directory: URL) throws {
        do {
            try FileManager.default.removeItem(at: packages(in: directory))
        } catch CocoaError.fileNoSuchFile {}
    }

    /// Returns the location of an installed theme's package.
    ///
    /// - Parameters:
    ///   - entry: The installed theme.
    ///   - directory: The catalog's folder.
    /// - Returns: The package's location.
    static func package(for entry: ThemeEntry, in directory: URL) -> URL {
        packages(in: directory).appendingPathComponent(entry.revision.uuidString + ".xtheme")
    }

    /// Returns the folder of installed packages.
    ///
    /// - Parameter directory: The catalog's folder.
    /// - Returns: The packages folder.
    private static func packages(in directory: URL) -> URL {
        directory.appendingPathComponent("Packages")
    }

    /// Moves a folder in one atomic rename that fails when the destination exists.
    ///
    /// - Parameters:
    ///   - source: The folder to move.
    ///   - destination: The new location on the same volume.
    /// - Throws: A file system error.
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
