import SwiftUI

/// Keeps an overlapping card opaque while it's pressed; selection lifts the chosen card instead.
struct TokenCardButtonStyle: ButtonStyle {
    /// Shows the card unchanged, so the cards below it never show through.
    /// - Parameter configuration: The button's label and press state.
    /// - Returns: The card as it is.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

extension ButtonStyle where Self == TokenCardButtonStyle {
    /// The style that keeps overlapping token cards opaque while pressed.
    static var tokenCard: TokenCardButtonStyle { TokenCardButtonStyle() }
}
