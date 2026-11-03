import Foundation

/// The theme selection and catalog entries at one revision.
nonisolated struct AppearanceSnapshot: Sendable, Equatable {
    let revision: UInt64
    let preferences: AppearancePreferences
    let entries: [UUID: ThemeEntry]
    /// The entries with bundled themes first, then by name.
    let orderedEntries: [ThemeEntry]
    let orderedEntryIDs: [UUID]

    /// Creates a snapshot.
    ///
    /// - Parameters:
    ///   - revision: The revision of the saved state.
    ///   - preferences: The app's theme selection.
    ///   - entries: The bundled and installed entries, keyed by identity.
    init(revision: UInt64, preferences: AppearancePreferences, entries: [UUID: ThemeEntry]) {
        self.revision = revision
        self.preferences = preferences
        self.entries = entries
        orderedEntries = entries.values.sorted {
            if $0.origin != $1.origin { return $0.origin == .builtIn }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }
        orderedEntryIDs = orderedEntries.map(\.id)
    }

    /// The app's selected theme, or `nil` for the original appearance.
    var theme: ThemeEntry? { preferences.themeID.flatMap { entries[$0] } }
}
