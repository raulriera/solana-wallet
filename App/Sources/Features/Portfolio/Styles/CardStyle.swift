import SwiftUI

/// The way the portfolio presents its tokens.
nonisolated struct CardStyle: Equatable, Sendable {
    /// The way the portfolio lists its tokens.
    nonisolated enum Layout: Equatable, Sendable {
        /// Overlapping cards, each tinted from its logo.
        case cards
        /// Native list rows.
        case rows
    }

    /// The way a card turns its logo color into a background.
    nonisolated enum Colors: Equatable, Sendable {
        /// A light tint of the logo color, with dark text.
        case pastel
        /// The logo color itself, with dark or white text by brightness.
        case vivid
    }

    var layout = Layout.cards
    var colors = Colors.pastel
    var fontDesign = Font.Design.rounded
    var cornerRadius: CGFloat = 22
}
