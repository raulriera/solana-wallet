import Foundation

/// Lightweight catalog metadata, independent of image bytes and resolved colors.
nonisolated struct ThemeEntry: Codable, Sendable, Equatable, Identifiable {
    /// Whether the app supplies the theme or the user installs it.
    enum Origin: String, Codable, Sendable {
        case builtIn
        case custom
    }

    let id: UUID
    let name: String
    let origin: Origin
    let revision: UUID

    /// Creates a catalog entry identifying one installed revision.
    /// - Parameters:
    ///   - id: The manifest's stable identity.
    ///   - name: The theme's display name, which need not be unique.
    ///   - origin: The authority that owns the package.
    ///   - revision: A new token for each installation, used to reject stale confirmations.
    init(id: UUID, name: String, origin: Origin, revision: UUID = UUID()) {
        self.id = id
        self.name = name
        self.origin = origin
        self.revision = revision
    }
}

/// An immutable theme supplied by app composition from bundled resources.
nonisolated struct BundledTheme: Sendable {
    let entry: ThemeEntry
    let url: URL

    /// Declares bundled metadata without reading its images during catalog construction.
    /// - Parameters:
    ///   - id: The bundled manifest's identity.
    ///   - name: The bundled manifest's name.
    ///   - url: Its app-owned package directory.
    init(id: UUID, name: String, url: URL) {
        entry = ThemeEntry(id: id, name: name, origin: .builtIn, revision: id)
        self.url = url
    }
}
