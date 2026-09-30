import Foundation

/// Persists local selections independently of scene navigation and theme rendering.
nonisolated protocol AppearanceStoring: Sendable {
    /// Loads a coherent snapshot and clears references to unavailable themes.
    /// - Returns: Current preferences and lightweight catalog entries.
    /// - Throws: A storage or pre-commit cancellation error.
    func load() async throws -> AppearanceSnapshot

    /// Changes one scope against the latest stored state without losing other window edits.
    /// - Parameters:
    ///   - themeID: The selected identity, or `nil` for the original appearance/application inheritance.
    ///   - scope: The application or wallet whose preference changes.
    /// - Returns: The committed snapshot.
    /// - Throws: An unavailable-theme, storage, or pre-commit cancellation error.
    func select(_ themeID: UUID?, for scope: AppearancePreferences.Scope) async throws -> AppearanceSnapshot

    /// Restores the original built-in appearance and removes every wallet override.
    /// - Returns: The committed snapshot, preserving installed packages.
    /// - Throws: A storage or pre-commit cancellation error.
    func reset() async throws -> AppearanceSnapshot
}
