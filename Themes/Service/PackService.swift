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
        try Self.requireLocalURL(url)
        try Task.checkCancellation()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Pack, any Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result {
                try Task.checkCancellation()
                return try PackageFiles.read(at: coordinatedURL)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
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
        let manifest = Manifest(id: pack.id, name: pack.name, colors: resolve(pack, defaults: defaults).values,
                                assets: pack.manifest.assets)
        try Self.write(manifest: manifest, assets: pack.assets, to: url)
    }

    /// Writes a new theme containing every supplied default color.
    /// - Parameters:
    ///   - name: The new theme's display name.
    ///   - defaults: Complete app-owned palettes.
    ///   - url: The caller-approved destination.
    /// - Throws: A validation, file-access, or pre-commit cancellation error.
    @concurrent
    public func exportTemplate(named name: String, defaults: Colors, to url: URL) async throws {
        try Manifest.validateName(name)
        let manifest = Manifest(id: UUID(), name: name, colors: defaults.values, assets: [:])
        try Self.write(manifest: manifest, assets: [:], to: url)
    }

    /// Prepares a full package before performing its coordinated atomic write.
    /// - Parameters:
    ///   - manifest: The complete exported manifest.
    ///   - assets: Validated asset snapshots.
    ///   - url: The local destination, with replacement approved by the caller.
    /// - Throws: A file-access, serialization, or pre-commit cancellation error.
    private static func write(manifest: Manifest, assets: [String: Asset], to url: URL) throws {
        try requireLocalURL(url)
        try Task.checkCancellation()
        let wrapper = try PackageFiles.wrapper(manifest: manifest, assets: assets)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Void, any Error>?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { destination in
            result = Result {
                try Task.checkCancellation()
                try wrapper.write(to: destination, options: .atomic, originalContentsURL: nil)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        try result.get()
    }

    /// Rejects remote URLs before any file-system or provider access.
    /// - Parameter url: The proposed package location.
    /// - Throws: A validation error for non-file URLs.
    private static func requireLocalURL(_ url: URL) throws {
        guard url.isFileURL else {
            throw ValidationError(path: "package", reason: "Expected a local file URL.")
        }
    }
}
