import Foundation

/// The private folder and bundled themes that the catalog and the preferences store share.
nonisolated struct ThemeStorage: Sendable {
    /// App-private persistent storage for installed themes and appearance preferences.
    let directory: URL
    /// The immutable bundled themes, keyed by identity.
    let builtIns: [UUID: BundledTheme]

    /// Keeps the folder and the bundled themes without reading storage or any theme package.
    /// - Parameters:
    ///   - directory: App-private persistent storage.
    ///   - builtIns: Immutable bundled themes supplied by app composition, each with its own identity.
    init(directory: URL, builtIns: [BundledTheme]) {
        self.directory = directory
        self.builtIns = Dictionary(uniqueKeysWithValues: builtIns.map { ($0.entry.id, $0) })
    }

    /// The bundled themes' catalog entries, keyed by identity.
    var builtInEntries: [UUID: ThemeEntry] {
        builtIns.mapValues(\.entry)
    }
}
