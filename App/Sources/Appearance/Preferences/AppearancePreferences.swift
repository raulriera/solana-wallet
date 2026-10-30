import Foundation

/// The selected themes of the app and each wallet.
nonisolated struct AppearancePreferences: Codable, Sendable, Equatable {
    /// What a theme selection applies to: the app or one wallet.
    enum Scope: Sendable, Hashable {
        case application
        /// A wallet, by its recovery identifier.
        case wallet(UUID)
    }

    /// The app's theme, or `nil` for the original appearance.
    private(set) var appThemeID: UUID?
    /// The themes of wallets with their own selection, keyed by recovery identifier.
    private(set) var walletThemeIDs: [UUID: UUID] = [:]

    /// Creates preferences that use the original appearance everywhere.
    init() {}

    /// Returns the theme of a wallet, or the app's theme when the wallet has none.
    ///
    /// - Parameter recoveryID: The wallet's recovery identifier, or `nil` for the app.
    /// - Returns: The theme's identity, or `nil` for the original appearance.
    func themeID(for recoveryID: UUID?) -> UUID? {
        recoveryID.flatMap { walletThemeIDs[$0] } ?? appThemeID
    }

    /// Sets the theme of the app or a wallet.
    ///
    /// - Parameters:
    ///   - themeID: The theme, or `nil` to clear the selection.
    ///   - scope: The app or wallet to change.
    mutating func select(_ themeID: UUID?, for scope: Scope) {
        switch scope {
        case .application: appThemeID = themeID
        case .wallet(let id): walletThemeIDs[id] = themeID
        }
    }

    /// Clears every selection of a theme.
    ///
    /// - Parameter themeID: The theme to clear.
    mutating func forget(_ themeID: UUID) {
        if appThemeID == themeID { appThemeID = nil }
        walletThemeIDs = walletThemeIDs.filter { $0.value != themeID }
    }

    /// Clears the selections of themes that aren't available.
    ///
    /// - Parameter available: The identities of the available themes.
    mutating func reconcile(available: Set<UUID>) {
        if let appThemeID, !available.contains(appThemeID) { self.appThemeID = nil }
        walletThemeIDs = walletThemeIDs.filter { available.contains($0.value) }
    }
}
