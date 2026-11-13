import Foundation
import Observation

/// An observable source of the app's appearance preferences.
@MainActor protocol AppearanceCoordinating: AnyObject, Observable {
    var snapshot: AppearanceSnapshot? { get }

    /// Loads the preferences, first resetting them when the person requests it in Settings.
    ///
    /// - Throws: A storage or preferences error.
    func activate() async throws

    /// Loads the preferences again.
    ///
    /// - Throws: A storage or cancellation error.
    func reload() async throws

    /// Discards the loaded preferences and loads them again.
    ///
    /// - Throws: A storage or cancellation error.
    func restart() async throws

    /// Saves and publishes the theme of the app.
    ///
    /// - Parameter themeID: The theme, or `nil` to clear the selection.
    /// - Throws: A selection, storage, or cancellation error.
    func select(_ themeID: UUID?) async throws

    /// Saves and publishes the way the portfolio lists its tokens.
    ///
    /// - Parameter layout: The token layout.
    /// - Throws: A storage or cancellation error.
    func select(_ layout: CardStyle.Layout) async throws

    /// Clears and publishes the selection of a theme.
    ///
    /// - Parameter themeID: The theme to clear.
    /// - Throws: A storage or cancellation error.
    func forget(_ themeID: UUID) async throws
}

extension AppearanceCoordinating {
    /// The loaded preferences, or the defaults until they load.
    var preferences: AppearancePreferences { snapshot?.preferences ?? AppearancePreferences() }
}
