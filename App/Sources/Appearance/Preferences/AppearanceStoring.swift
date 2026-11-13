import Foundation

/// A store of appearance preferences.
nonisolated protocol AppearanceStoring: Sendable {
    /// Loads the preferences and clears the selection of an unavailable theme.
    ///
    /// - Returns: The preferences and catalog entries.
    /// - Throws: A storage or cancellation error.
    func load() async throws -> AppearanceSnapshot

    /// Saves the theme of the app.
    ///
    /// - Parameter themeID: The theme, or `nil` to clear the selection.
    /// - Returns: The saved snapshot.
    /// - Throws: An unavailable-theme, storage, or cancellation error.
    func select(_ themeID: UUID?) async throws -> AppearanceSnapshot

    /// Saves the way the portfolio lists its tokens.
    ///
    /// - Parameter layout: The token layout.
    /// - Returns: The saved snapshot.
    /// - Throws: A storage or cancellation error.
    func select(_ layout: CardStyle.Layout) async throws -> AppearanceSnapshot

    /// Clears the selection of a theme without removing the theme.
    ///
    /// - Parameter themeID: The theme to clear.
    /// - Returns: The saved snapshot.
    /// - Throws: A storage or cancellation error.
    func forget(_ themeID: UUID) async throws -> AppearanceSnapshot

    /// Restores the default preferences.
    ///
    /// - Returns: The saved snapshot.
    /// - Throws: A storage or cancellation error.
    func reset() async throws -> AppearanceSnapshot
}
