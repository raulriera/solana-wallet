import Foundation

/// A store of theme selections.
nonisolated protocol AppearanceStoring: Sendable {
    /// Loads the selections and clears those of unavailable themes.
    ///
    /// - Returns: The selections and catalog entries.
    /// - Throws: A storage or cancellation error.
    func load() async throws -> AppearanceSnapshot

    /// Saves the theme of the app or a wallet.
    ///
    /// - Parameters:
    ///   - themeID: The theme, or `nil` to clear the selection.
    ///   - scope: The app or wallet to change.
    /// - Returns: The saved snapshot.
    /// - Throws: An unavailable-theme, storage, or cancellation error.
    func select(_ themeID: UUID?, for scope: AppearancePreferences.Scope) async throws -> AppearanceSnapshot

    /// Clears every selection of a theme without removing the theme.
    ///
    /// - Parameter themeID: The theme to clear.
    /// - Returns: The saved snapshot.
    /// - Throws: A storage or cancellation error.
    func forget(_ themeID: UUID) async throws -> AppearanceSnapshot

    /// Clears every theme selection.
    ///
    /// - Returns: The saved snapshot.
    /// - Throws: A storage or cancellation error.
    func reset() async throws -> AppearanceSnapshot
}
