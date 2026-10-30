import Foundation

/// The saved state of the theme catalog: installed themes and selections.
nonisolated struct CatalogState: Codable, Sendable {
    var revision: UInt64 = 0
    var customEntries: [UUID: ThemeEntry] = [:]
    var preferences = AppearancePreferences()

    /// Creates an empty state.
    init() {}

    /// Returns the installed entries combined with the bundled ones.
    ///
    /// - Parameter builtIns: The bundled entries, keyed by identity.
    /// - Returns: Every entry, keyed by identity.
    /// - Throws: An invalid-storage error when an installed entry has a bundled identity.
    func entries(including builtIns: [UUID: ThemeEntry]) throws -> [UUID: ThemeEntry] {
        try customEntries.merging(builtIns) { _, _ in throw ThemeCatalogError.invalidStorage }
    }
}
