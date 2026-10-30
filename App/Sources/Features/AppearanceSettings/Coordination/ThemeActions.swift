import Foundation

/// Actions that select and remove themes.
@MainActor protocol ThemeActions: AnyObject {
    /// Selects the theme of the app or a wallet.
    ///
    /// - Parameters:
    ///   - id: The theme, or `nil` to clear the selection.
    ///   - scope: The app or wallet to change.
    func select(_ id: UUID?, for scope: AppearancePreferences.Scope)

    /// Removes an installed theme.
    ///
    /// - Parameter entry: The installed theme to remove.
    func remove(_ entry: ThemeEntry)
}
