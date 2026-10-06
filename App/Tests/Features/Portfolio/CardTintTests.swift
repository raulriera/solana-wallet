import SwiftUI
import Testing
@testable import widgets

/// Checks that a card's text reads on the color its logo gives the card.
struct CardTintTests {
    /// Every logo color, dark or light, leaves the text at the 4.5:1 WCAG minimum on both gradient stops.
    /// - Parameters:
    ///   - logo: A logo color, from dark and saturated to light.
    ///   - colors: How the card turns the logo color into a background.
    @Test(arguments: [
        ArtworkColor(red: 0, green: 0, blue: 0.25), ArtworkColor(red: 0.3, green: 0, blue: 0),
        ArtworkColor(red: 0, green: 0.7, blue: 0), ArtworkColor(red: 0, green: 0.6, blue: 0.6),
        ArtworkColor(red: 0.6, green: 0.27, blue: 1), ArtworkColor(red: 0.95, green: 0.9, blue: 0.2),
    ], [CardStyle.Colors.pastel, .vivid])
    func `Card text reads at 4.5 to 1 on every logo color`(logo: ArtworkColor, colors: CardStyle.Colors) {
        let tint = CardTint(logo: logo, colors: colors)
        #expect(contrast(tint.text, tint.top) >= 4.5)
        #expect(contrast(tint.text, tint.bottom) >= 4.5)
    }

    /// Pastel cards stay light whatever the logo, so their text stays dark.
    @Test
    func `Pastel cards keep dark text`() {
        let tint = CardTint(logo: ArtworkColor(red: 0, green: 0, blue: 0.25), colors: .pastel)
        #expect(contrast(tint.text, .white) > contrast(tint.text, .black))
    }

    /// Computes the WCAG contrast ratio between two colors resolved without a view.
    /// - Parameters:
    ///   - first: One color.
    ///   - second: The other color.
    /// - Returns: A ratio from 1 for equal colors to 21 for black and white.
    private func contrast(_ first: Color, _ second: Color) -> Double {
        // Resolved components are linear, so they weigh into the relative luminance directly.
        func luminance(_ color: Color) -> Double {
            let resolved = color.resolve(in: EnvironmentValues())
            return 0.2126 * Double(resolved.linearRed) + 0.7152 * Double(resolved.linearGreen)
                + 0.0722 * Double(resolved.linearBlue)
        }
        let (a, b) = (luminance(first), luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
