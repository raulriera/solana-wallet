public import Foundation

/// A validated snapshot of a theme package.
public struct Pack: Sendable, Equatable {
    public var id: UUID { manifest.id }
    public var name: String { manifest.name }
    let assets: [String: Asset]
    let manifest: Manifest

    /// Creates a pack from a validated manifest and its assets.
    ///
    /// - Parameters:
    ///   - manifest: The validated manifest.
    ///   - assets: The images, keyed by declaration name.
    init(manifest: Manifest, assets: [String: Asset]) {
        self.manifest = manifest
        self.assets = assets
    }
}

/// A validated image in a theme package.
struct Asset: Sendable, Equatable {
    let data: Data
    let path: String

    /// Creates an asset.
    ///
    /// - Parameters:
    ///   - data: Complete PNG or JPEG data.
    ///   - path: The package-relative path inside the Assets directory.
    init(data: Data, path: String) {
        self.data = data
        self.path = path
    }
}
