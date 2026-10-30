import Foundation

/// A store that saves theme selections in the theme catalog's folder.
nonisolated struct AppearanceStore: AppearanceStoring {
    /// A change to the selections, given the available entries.
    private typealias Mutation = @Sendable (inout AppearancePreferences, [UUID: ThemeEntry]) throws -> Void

    private let storage: ThemeStorage

    /// Creates a store.
    ///
    /// - Parameters:
    ///   - directory: The folder that stores installed themes.
    ///   - builtIns: The bundled themes.
    init(directory: URL,
         builtIns: [BundledTheme] = []) {
        storage = ThemeStorage(directory: directory, builtIns: builtIns)
    }

    @concurrent
    func load() async throws -> AppearanceSnapshot {
        try await update { _, _ in }
    }

    @concurrent
    func select(_ themeID: UUID?, for scope: AppearancePreferences.Scope) async throws -> AppearanceSnapshot {
        try await update { preferences, entries in
            if let themeID, entries[themeID] == nil { throw ThemeCatalogError.changed }
            preferences.select(themeID, for: scope)
        }
    }

    @concurrent
    func forget(_ themeID: UUID) async throws -> AppearanceSnapshot {
        try await update { preferences, _ in preferences.forget(themeID) }
    }

    @concurrent
    func reset() async throws -> AppearanceSnapshot {
        try await update { preferences, _ in preferences = AppearancePreferences() }
    }

    /// Applies a change to the saved selections in one transaction.
    ///
    /// - Parameter mutation: The change to apply.
    /// - Returns: The resulting snapshot.
    /// - Throws: A mutation, storage, or cancellation error.
    private func update(
        _ mutation: @escaping Mutation
    ) async throws -> AppearanceSnapshot {
        try await CatalogIO.perform { checkCancellation in
            var state = try CatalogFiles.state(in: storage.directory)
            let entries = try state.entries(including: storage.builtInEntries)
            let previous = state.preferences
            state.preferences.reconcile(available: Set(entries.keys))
            try mutation(&state.preferences, entries)
            if state.preferences != previous {
                state = try CatalogFiles.commit(state, in: storage.directory, checkCancellation: checkCancellation)
            }
            return AppearanceSnapshot(revision: state.revision, preferences: state.preferences, entries: entries)
        }
    }
}
