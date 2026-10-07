import SwiftUI

/// A card's gradient and the text color that reads on it, derived from the card's logo color.
///
/// The text always reads at 4.5:1 or more on both gradient stops, the WCAG minimum for small text.
nonisolated struct CardTint {
    /// The gradient's top color.
    let top: Color
    /// The gradient's bottom color.
    let bottom: Color
    /// The color of the card's text.
    let text: Color
    /// The gradient stop with the least contrast against the text; supporting text fades toward it.
    let textBackground: Color

    /// Derives a card's colors from its logo.
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
        // A dark logo moves toward white under dark text, and a light one toward black under white text.
        let away = ink == white ? ArtworkColor(red: 0, green: 0, blue: 0) : white
        while base.contrast(with: ink) < 4.5 {
            base = base.mixed(with: away, by: 0.1)
        }
        // The second stop moves further from the text, so the text reads at least as well there.
        let other = base.mixed(with: away, by: 0.2)
        (top, bottom) = ink == white ? (base.color, other.color) : (other.color, base.color)
        text = ink.color
        textBackground = base.color
    }
}
