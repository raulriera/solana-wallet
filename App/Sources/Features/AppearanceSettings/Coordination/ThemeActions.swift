import Foundation

/// Actions that select and remove themes.
@MainActor protocol ThemeActions: AnyObject {
    /// Selects the theme of the app.
    ///
    /// - Parameter id: The theme, or `nil` to clear the selection.
    func select(_ id: UUID?)

    /// Removes an installed theme.
    ///
    /// - Parameter entry: The installed theme to remove.
    func remove(_ entry: ThemeEntry)
}
