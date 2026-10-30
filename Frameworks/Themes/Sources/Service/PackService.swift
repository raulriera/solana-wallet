public import Foundation

/// A service that reads and writes theme packages with file coordination.
public struct PackService: PackServicing {
    /// Creates a pack service.
    public init() {}

    @concurrent
    public func read(from url: URL) async throws -> Pack {
        try await FileAccess.perform(at: url) { coordinatedURL, access in
            try PackageFiles.read(at: coordinatedURL, checkCancellation: access.checkCancellation)
        }
    }

    @concurrent
    public func save(_ pack: Pack, to url: URL) async throws {
        try await Self.write(assets: pack.assets, to: url) { pack.manifest }
    }

    public func resolve(_ pack: Pack, defaults: Colors) -> Colors {
        defaults.applying(pack.manifest.colors)
    }

    @concurrent
    public func exportTemplate(named name: String, defaults: Colors, to url: URL) async throws {
        try await Self.write(assets: [:], to: url) {
            try Manifest.validateName(name)
            return Manifest(id: UUID(), name: name, colors: defaults.values, assets: [:])
        }
    }

    /// Writes a package atomically on the file queue.
    ///
    /// - Parameters:
    ///   - assets: The package's validated assets.
    ///   - url: The local destination package URL.
    ///   - manifest: A closure that creates the manifest.
    /// - Throws: A file-access, serialization, or cancellation error.
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
