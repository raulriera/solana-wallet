import SwiftUI

/// A card's gradient and the text color that reads on it, derived from the card's logo color.
nonisolated struct CardTint {
    let top: Color
    let bottom: Color
    let text: Color
    /// The gradient stop with the least contrast against the text.
    let textBackground: Color

    /// Creates a card's colors from its logo color.
    ///
    /// - Parameters:
    ///   - logo: The logo's representative color.
    ///   - colors: How the card turns the logo color into a background.
    init(logo: ArtworkColor, colors: CardStyle.Colors) {
        let dark = ArtworkColor(red: 0.11, green: 0.13, blue: 0.17)
        let white = ArtworkColor(red: 1, green: 1, blue: 1)
        var base: ArtworkColor
        let ink: ArtworkColor
        switch colors {
        case .pastel:
            base = logo.mixed(with: white, by: 0.38)
            ink = dark
        case .vivid:
            base = logo
            ink = logo.contrast(with: white) >= logo.contrast(with: dark) ? white : dark
        }
        let away = ink == white ? ArtworkColor(red: 0, green: 0, blue: 0) : white
        while base.contrast(with: ink) < 4.5 {
            base = base.mixed(with: away, by: 0.1)
        }
        let other = base.mixed(with: away, by: 0.2)
        (top, bottom) = ink == white ? (base.color, other.color) : (other.color, base.color)
        text = ink.color
        textBackground = base.color
    }
}
