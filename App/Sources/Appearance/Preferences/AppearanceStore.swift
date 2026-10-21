import Foundation

/// Serializes preference mutations with catalog changes on the shared background I/O queue.
nonisolated struct AppearanceStore: AppearanceStoring {
    /// Mutates preferences using the available catalog entries without suspending.
    private typealias Mutation = @Sendable (inout AppearancePreferences, [UUID: ThemeEntry]) throws -> Void

    private let storage: ThemeStorage

    /// Configures local preferences without reading storage or any theme packages.
    /// - Parameters:
    ///   - directory: The same app-private directory used by the catalog.
    ///   - builtIns: The same immutable bundled themes supplied to the catalog.
    init(directory: URL,
         builtIns: [BundledTheme] = []) {
        storage = ThemeStorage(directory: directory, builtIns: builtIns)
    }

    /// Loads and reconciles selections without opening a theme package.
    /// - Returns: The latest coherent metadata snapshot.
    /// - Throws: A storage or cancellation error.
    @concurrent
    func load() async throws -> AppearanceSnapshot {
        try await update { _, _ in }
    }

    /// Persists one application or wallet selection while retaining unrelated edits.
    /// - Parameters:
    ///   - themeID: An available identity, or `nil` to remove the explicit selection.
    ///   - scope: The preference to change.
    /// - Returns: The committed snapshot.
    /// - Throws: A changed-catalog, storage, or cancellation error.
    @concurrent
    func select(_ themeID: UUID?, for scope: AppearancePreferences.Scope) async throws -> AppearanceSnapshot {
        try await update { preferences, entries in
            if let themeID, entries[themeID] == nil { throw ThemeCatalogError.changed }
            preferences.select(themeID, for: scope)
        }
    }

    /// Clears every selection of one theme while retaining the installed catalog.
    /// - Parameter themeID: The theme that the application and every wallet stop using.
    /// - Returns: The committed snapshot.
    /// - Throws: A storage or cancellation error.
    @concurrent
    func forget(_ themeID: UUID) async throws -> AppearanceSnapshot {
        try await update { preferences, _ in preferences.forget(themeID) }
    }

    /// Clears all selections while retaining the installed catalog.
    /// - Returns: The committed snapshot using the original built-in appearance.
    /// - Throws: A storage or cancellation error.
    @concurrent
    func reset() async throws -> AppearanceSnapshot {
        try await update { preferences, _ in preferences = AppearancePreferences() }
    }

    /// Applies a small mutation to the latest state within one filesystem transaction.
    /// - Parameter mutation: Selection changes that never suspend or read package data.
    /// - Returns: The resulting snapshot; no-op changes retain their revision.
    /// - Throws: A mutation, storage, or pre-commit cancellation error.
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
