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
    }
}

nonisolated private extension ArtworkColor {
    /// The color as SwiftUI draws it.
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    /// The WCAG relative luminance, from 0 for black to 1 for white.
    var luminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The WCAG contrast ratio between this color and another.
    /// - Parameter other: The color that this one sits on or under.
    /// - Returns: A ratio from 1 for equal colors to 21 for black and white.
    func contrast(with other: ArtworkColor) -> Double {
        let (lighter, darker) = (max(luminance, other.luminance), min(luminance, other.luminance))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Mixes this color with another in sRGB.
    /// - Parameters:
    ///   - other: The color to mix in.
    ///   - fraction: How much of the other color to use, from 0 to 1.
    /// - Returns: The mixed color.
    func mixed(with other: ArtworkColor, by fraction: Double) -> ArtworkColor {
        ArtworkColor(red: red + (other.red - red) * fraction, green: green + (other.green - green) * fraction,
                     blue: blue + (other.blue - blue) * fraction)
    }
}
