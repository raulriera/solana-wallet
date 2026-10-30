import Foundation

/// A catalog theme's identity, name, origin, and revision.
nonisolated struct ThemeEntry: Codable, Sendable, Equatable, Identifiable {
    /// The source of a theme.
    enum Origin: String, Codable, Sendable {
        case builtIn
        case custom
    }

    let id: UUID
    let name: String
    let origin: Origin
    let revision: UUID

    /// Creates a catalog entry.
    ///
    /// - Parameters:
    ///   - id: The theme's identity.
    ///   - name: The theme's display name.
    ///   - origin: The source of the theme.
    ///   - revision: The identity of this installation.
    init(id: UUID, name: String, origin: Origin, revision: UUID = UUID()) {
        self.id = id
        self.name = name
        self.origin = origin
        self.revision = revision
    }
}

/// A theme bundled with the app.
nonisolated struct BundledTheme: Sendable {
    let entry: ThemeEntry
    let url: URL

    /// Creates a bundled theme.
    ///
    /// - Parameters:
    ///   - id: The theme's identity.
    ///   - name: The theme's display name.
    ///   - url: The location of the theme's package.
    init(id: UUID, name: String, url: URL) {
        entry = ThemeEntry(id: id, name: name, origin: .builtIn, revision: id)
        self.url = url
    }
}
