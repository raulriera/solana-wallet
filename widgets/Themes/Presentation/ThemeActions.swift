import Foundation

/// The window-owned commands available to theme selection controls.
@MainActor protocol ThemeActions: AnyObject {
    /// Persists a choice before publishing its selected appearance.
    /// - Parameters:
    ///   - id: The chosen theme, or `nil` for the application baseline or wallet inheritance.
    ///   - scope: The application default or wallet override to change.
    func select(_ id: UUID?, for scope: AppearancePreferences.Scope)

    /// Removes the exact custom revision approved by the user.
    /// - Parameter entry: The entry retained by the deletion confirmation.
    func remove(_ entry: ThemeEntry)
}
