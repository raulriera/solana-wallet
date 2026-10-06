import SwiftUI

/// How the portfolio presents its tokens; the app supplies these defaults until a theme chooses others.
nonisolated struct CardStyle: Equatable, Sendable {
    /// How the portfolio lists its tokens.
    nonisolated enum Layout: Equatable, Sendable {
        /// Overlapping cards, each tinted from its logo.
        case cards
        /// Native list rows.
        case rows
    }

    /// How a card turns its logo color into a background.
    nonisolated enum Colors: Equatable, Sendable {
        /// A light tint of the logo color, with dark text.
        case pastel
        /// The logo color itself, with dark or white text by brightness.
        case vivid
    }

    /// How the portfolio lists its tokens.
    var layout = Layout.cards
    /// How a card turns its logo color into a background.
    var colors = Colors.pastel
    /// The font design of a card's text.
    var fontDesign = Font.Design.rounded
    /// The corner radius of a card.
    var cornerRadius: CGFloat = 22
}

extension EnvironmentValues {
    /// The window's token presentation options.
    @Entry var cardStyle = CardStyle()
}
