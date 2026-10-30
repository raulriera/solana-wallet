import Foundation

/// The theme catalog's folder and bundled themes.
nonisolated struct ThemeStorage: Sendable {
    let directory: URL
    let builtIns: [UUID: BundledTheme]

    /// Creates theme storage.
    ///
    /// - Parameters:
    ///   - directory: The folder that stores installed themes.
    ///   - builtIns: The bundled themes, each with a unique identity.
    init(directory: URL, builtIns: [BundledTheme]) {
        self.directory = directory
        self.builtIns = Dictionary(uniqueKeysWithValues: builtIns.map { ($0.entry.id, $0) })
    }

    var builtInEntries: [UUID: ThemeEntry] {
        builtIns.mapValues(\.entry)
    }
}
