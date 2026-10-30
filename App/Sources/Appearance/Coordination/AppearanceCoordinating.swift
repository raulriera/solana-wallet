import Foundation
import Observation

/// An observable source of the app's and wallets' theme selections.
@MainActor protocol AppearanceCoordinating: AnyObject, Observable {
    var snapshot: AppearanceSnapshot? { get }

    /// Loads the theme selections, first resetting them when the person requests it in Settings.
    ///
    /// - Throws: A storage or preferences error.
    func activate() async throws

    /// Loads the theme selections again.
    ///
    /// - Throws: A storage or cancellation error.
    func reload() async throws

    /// Discards the loaded theme selections and loads them again.
    ///
    /// - Throws: A storage or cancellation error.
    func restart() async throws

    /// Saves and publishes the theme of the app or a wallet.
    ///
    /// - Parameters:
    ///   - themeID: The theme, or `nil` to clear the selection.
    ///   - scope: The app or wallet to change.
    /// - Throws: A selection, storage, or cancellation error.
    func select(_ themeID: UUID?, for scope: AppearancePreferences.Scope) async throws

    /// Clears and publishes every selection of a theme.
    ///
    /// - Parameter themeID: The theme to clear.
    /// - Throws: A storage or cancellation error.
    func forget(_ themeID: UUID) async throws
}
