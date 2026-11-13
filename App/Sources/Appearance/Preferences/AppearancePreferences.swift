import Foundation

/// The selected theme and token layout of the app.
nonisolated struct AppearancePreferences: Codable, Sendable, Equatable {
    /// The app's theme, or `nil` for the original appearance.
    var themeID: UUID?
    /// The way the portfolio lists its tokens.
    var tokenLayout = CardStyle.Layout.cards

    /// Creates preferences that use the original appearance and token cards.
    init() {}

    /// Clears the selection of a theme.
    ///
    /// - Parameter themeID: The theme to clear.
    mutating func forget(_ themeID: UUID) {
        if self.themeID == themeID { self.themeID = nil }
    }

    /// Clears the selection of a theme that isn't available.
    ///
    /// - Parameter available: The identities of the available themes.
    mutating func reconcile(available: Set<UUID>) {
        if let themeID, !available.contains(themeID) { self.themeID = nil }
    }
}
