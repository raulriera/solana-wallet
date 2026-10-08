import SwiftUI
import Testing
@testable import widgets

/// Checks that a card's text reads on the color its logo gives the card.
struct CardTintTests {
    /// Logo colors from dark and saturated to light, plus the gray that cards without a logo color use.
    private static let logos = [
        ArtworkColor(red: 0, green: 0, blue: 0.25), ArtworkColor(red: 0.3, green: 0, blue: 0),
        ArtworkColor(red: 0, green: 0.7, blue: 0), ArtworkColor(red: 0, green: 0.6, blue: 0.6),
        ArtworkColor(red: 0.6, green: 0.27, blue: 1), ArtworkColor(red: 0.95, green: 0.9, blue: 0.2),
        .placeholder,
    ]

    /// Every logo color, dark or light, leaves the text at the 4.5:1 WCAG minimum on both gradient stops.
    /// - Parameters:
    ///   - logo: A logo color, from dark and saturated to light.
    ///   - colors: How the card turns the logo color into a background.
    @Test(arguments: logos, [CardStyle.Colors.pastel, .vivid])
    func `Card text reads at 4.5 to 1 on every logo color`(logo: ArtworkColor, colors: CardStyle.Colors) {
        let tint = CardTint(logo: logo, colors: colors)
        #expect(contrast(tint.text, tint.top) >= 4.5)
        #expect(contrast(tint.text, tint.bottom) >= 4.5)
    }

    /// Supporting text, such as the name and the 24-hour change, also stays at 4.5:1 on both gradient stops.
    /// - Parameters:
    ///   - logo: A logo color, from dark and saturated to light.
    ///   - colors: How the card turns the logo color into a background.
    @Test(arguments: logos, [CardStyle.Colors.pastel, .vivid])
    func `Secondary card text reads at 4.5 to 1 on every logo color`(logo: ArtworkColor, colors: CardStyle.Colors) {
        let tint = CardTint(logo: logo, colors: colors)
        let secondary = Color(ReadableSecondary(text: tint.text, background: tint.textBackground)
            .resolve(in: EnvironmentValues()))
        #expect(contrast(secondary, tint.top) >= 4.5)
        #expect(contrast(secondary, tint.bottom) >= 4.5)
    }

    /// Text with room to spare fades until just above the 4.6:1 target, a margin over the 4.5:1 minimum.
    @Test
    func `Secondary text fades only as far as 4.6 to 1`() {
        let faded = Color(ReadableSecondary(text: .black, background: .white).resolve(in: EnvironmentValues()))
        #expect(contrast(faded, .white) >= 4.6)
        #expect(contrast(faded, .white) < 5)
    }

    /// Text that is already near the minimum keeps its color instead of fading below it.
    @Test
    func `Secondary text without room to fade keeps its color`() {
        let gray = Color(.sRGB, red: 0.46, green: 0.46, blue: 0.46)
        let kept = Color(ReadableSecondary(text: gray, background: .white).resolve(in: EnvironmentValues()))
        #expect(abs(contrast(kept, .white) - contrast(gray, .white)) < 0.001)
    }

    /// A see-through text color is measured as it shows on the background, so the faded color still reads.
    @Test
    func `See-through text fades from the color that shows`() {
        let environment = EnvironmentValues()
        let faded = ReadableSecondary.faded(Color.black.opacity(0.8).resolve(in: environment),
                                            on: Color.white.resolve(in: environment), toContrast: 4.6)
        #expect(faded.opacity == 1)
        #expect(contrast(Color(faded), .white) >= 4.6)
    }

    /// With Increase Contrast, supporting text stops fading at 7:1.
    @Test
    func `Increase Contrast keeps secondary text at 7 to 1`() {
        let environment = EnvironmentValues()
        let faded = ReadableSecondary.faded(Color.black.resolve(in: environment),
                                            on: Color.white.resolve(in: environment), toContrast: 7)
        #expect(contrast(Color(faded), .white) >= 7)
        #expect(contrast(Color(faded), .white) < 9)
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
