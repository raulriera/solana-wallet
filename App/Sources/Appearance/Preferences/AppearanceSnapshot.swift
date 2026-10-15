import Foundation

/// A coherent, lightweight catalog and preference snapshot for all wallet windows.
nonisolated struct AppearanceSnapshot: Sendable, Equatable {
    let revision: UInt64
    let preferences: AppearancePreferences
    let entries: [UUID: ThemeEntry]
    let orderedEntries: [ThemeEntry]
    /// Prepared identities that change only when list membership or order changes.
    let orderedEntryIDs: [UUID]

    /// Captures committed selections and their available catalog revisions.
    /// - Parameters:
    ///   - revision: The persistent state revision, ordered within one catalog directory.
    ///   - preferences: The current application and wallet selections.
    ///   - entries: Built-in and installed custom entries, without package or image data.
    init(revision: UInt64, preferences: AppearancePreferences, entries: [UUID: ThemeEntry]) {
        self.revision = revision
        self.preferences = preferences
        self.entries = entries
        // The store constructs snapshots on CatalogIO, so list preparation stays out of rendering.
        orderedEntries = entries.values.sorted {
            if $0.origin != $1.origin { return $0.origin == .builtIn }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }
        orderedEntryIDs = orderedEntries.map(\.id)
    }

    /// Looks up the selected revision using only in-memory values.
    /// - Parameter recoveryID: The window's wallet recovery identifier, or `nil` for application appearance.
    /// - Returns: The selected entry; `nil` uses the original built-in appearance.
    func theme(for recoveryID: UUID?) -> ThemeEntry? {
        preferences.themeID(for: recoveryID).flatMap { entries[$0] }
    }
}
