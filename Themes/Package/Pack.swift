public import Foundation

/// An independently owned, validated snapshot of an imported theme package.
/// Equality includes the manifest and all retained asset contents.
public struct Pack: Sendable, Equatable {
    public var id: UUID { manifest.id }
    public var name: String { manifest.name }
    public let assets: [String: Asset]
    let manifest: Manifest

    /// Creates a snapshot after validating the manifest and declared assets.
    /// - Parameters:
    ///   - manifest: The validated manifest.
    ///   - assets: Independently owned image bytes keyed by declaration name.
    init(manifest: Manifest, assets: [String: Asset]) {
        self.manifest = manifest
        self.assets = assets
    }
}

/// Validated image data that remains accessible after the imported URL's access ends.
public struct Asset: Sendable, Equatable {
    public let data: Data
    public let path: String

    /// Retains supported image data and its validated package-relative path.
    /// - Parameters:
    ///   - data: Complete PNG or JPEG data.
    ///   - path: The relative path inside the package's Assets directory.
    init(data: Data, path: String) {
        self.data = data
        self.path = path
    }
}
