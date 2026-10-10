import Foundation

/// Private metadata committed atomically so deletion and selection fallback cannot diverge.
nonisolated struct CatalogState: Codable, Sendable {
    var revision: UInt64 = 0
    var customEntries: [UUID: ThemeEntry] = [:]
    var preferences = AppearancePreferences()

    /// Creates the empty state used before the first local mutation.
    init() {}

    /// Combines installed metadata with immutable built-in descriptors.
    /// - Parameter builtIns: The app's configured built-in entries.
    /// - Returns: All available entries, indexed by identity.
    /// - Throws: A storage error if custom metadata collides with a protected built-in.
    func entries(including builtIns: [UUID: ThemeEntry]) throws -> [UUID: ThemeEntry] {
        try customEntries.merging(builtIns) { _, _ in throw ThemeCatalogError.invalidStorage }
    }
}
