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

    /// Creates a bundled theme from the package with its name among a bundle's themes.
    ///
    /// - Parameters:
    ///   - id: The theme's identity.
    ///   - name: The theme's display name, which is also its package's name.
    ///   - bundle: The bundle that holds the themes.
    /// - Returns: The theme, or `nil` when the bundle has no such package.
    init?(id: UUID, name: String, bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: name, withExtension: "xtheme", subdirectory: "Themes.bundle") else {
            return nil
        }
        self.init(id: id, name: name, url: url)
    }

    /// The built-in theme with the system's colors.
    static let original = BundledTheme(id: OriginalAppearance.id, name: "Original")
    /// The built-in Solana theme.
    // swift-format-ignore: NeverForceUnwrap
    static let solana = BundledTheme(id: UUID(uuidString: "3CE59F41-25A9-46B5-A2A2-0E76369FE403")!, name: "Solana")
}
