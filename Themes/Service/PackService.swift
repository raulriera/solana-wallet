public import Foundation

/// A stateless package service with operation-local serialization and file coordination.
public struct PackService: PackServicing {
    /// Creates a service without persistent state or app-owned defaults.
    public init() {}

    /// Reads a package under coordinated, security-scoped access.
    /// - Parameter url: The package directory selected by the caller.
    /// - Returns: A validated snapshot containing owned asset bytes.
    /// - Throws: A validation, file-access, or cancellation error.
    @concurrent
    public func read(from url: URL) async throws -> Pack {
        try await FileAccess.perform(at: url) { coordinatedURL, access in
            try PackageFiles.read(at: coordinatedURL, checkCancellation: access.checkCancellation)
        }
    }

    /// Resolves color overrides using the corresponding complete default palettes.
    /// - Parameters:
    ///   - pack: A validated imported snapshot.
    ///   - defaults: Complete app-owned palettes.
    /// - Returns: Complete semantic colors without modifying the pack or defaults.
    public func resolve(_ pack: Pack, defaults: Colors) -> Colors {
        defaults.applying(pack.manifest.colors)
    }

    /// Writes complete colors and owned assets while preserving the theme UUID.
    /// - Parameters:
    ///   - pack: The imported snapshot to export.
    ///   - defaults: Complete app-owned defaults for omitted settings.
    ///   - url: The caller-approved destination.
    /// - Throws: A file-access or pre-commit cancellation error.
    @concurrent
    public func export(_ pack: Pack, defaults: Colors, to url: URL) async throws {
        try await Self.write(assets: pack.assets, to: url) {
            Manifest(id: pack.id, name: pack.name, colors: resolve(pack, defaults: defaults).values,
                     assets: pack.manifest.assets)
        }
    }

    /// Writes a new theme containing every supplied default color.
    /// - Parameters:
    ///   - name: The new theme's display name.
    ///   - defaults: Complete app-owned palettes.
    ///   - url: The caller-approved destination.
    /// - Throws: A validation, file-access, or pre-commit cancellation error.
    @concurrent
    public func exportTemplate(named name: String, defaults: Colors, to url: URL) async throws {
        try await Self.write(assets: [:], to: url) {
            try Manifest.validateName(name)
            return Manifest(id: UUID(), name: name, colors: defaults.values, assets: [:])
        }
    }

    /// Prepares and atomically writes a package on the background file queue.
    /// - Parameters:
    ///   - assets: Validated asset snapshots.
    ///   - url: The local destination, with replacement approved by the caller.
    ///   - manifest: Creates the complete manifest within the background operation.
    /// - Throws: A file-access, serialization, or pre-commit cancellation error.
    private static func write(assets: [String: Asset], to url: URL,
                              manifest: @escaping @Sendable () throws -> Manifest) async throws {
        try await FileAccess.perform(at: url, writing: true) { destination, access in
            let wrapper = try PackageFiles.wrapper(manifest: manifest(), assets: assets,
                                                   checkCancellation: access.checkCancellation)
            try access.checkCancellation()
            try wrapper.write(to: destination, options: .atomic, originalContentsURL: nil)
        }
    }
}
