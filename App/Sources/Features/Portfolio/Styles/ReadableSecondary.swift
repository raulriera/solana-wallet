import SwiftUI

/// A lighter version of a text color for supporting details that still reads at 4.5:1 on its background.
///
/// The style fades the text color toward the background in small steps and stops before the contrast drops
/// below 4.6:1, a small margin over the WCAG minimum for small text, or below 7:1 with Increase Contrast.
/// A text color without room to fade stays as it shows on the background.
nonisolated struct ReadableSecondary: ShapeStyle {
    /// The primary text color to fade.
    let text: Color
    /// The color behind the text.
    let background: Color

    /// Resolves both colors for the current appearance and returns the faded text color.
    /// - Parameter environment: The environment that resolves the colors and reports Increase Contrast.
    /// - Returns: The lightest step of the text color that still reads at the target contrast.
    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        let target = environment.colorSchemeContrast == .increased ? 7.0 : 4.6
        return Self.faded(text.resolve(in: environment), on: background.resolve(in: environment), toContrast: target)
    }

    /// Fades a text color toward its background until one more step would read below the target contrast.
    /// - Parameters:
    ///   - text: The resolved primary text color; a see-through color is measured as it shows on the background.
    ///   - background: The resolved background color.
    ///   - target: The lowest contrast ratio the faded color may have.
    /// - Returns: An opaque color at the target contrast or more, or the text as it shows when it has no room to fade.
    static func faded(_ text: Color.Resolved, on background: Color.Resolved, toContrast target: Double) -> Color.Resolved {
        let surface = ArtworkColor(background)
        let ink = surface.mixed(with: ArtworkColor(text), by: Double(text.opacity))
        var faded = ink
        var fraction = 0.05
        while fraction < 1, ink.mixed(with: surface, by: fraction).contrast(with: surface) >= target {
            faded = ink.mixed(with: surface, by: fraction)
            fraction += 0.05
        }
        return Color.Resolved(colorSpace: .sRGB, red: Float(faded.red), green: Float(faded.green),
                              blue: Float(faded.blue), opacity: 1)
    }
}

nonisolated extension ShapeStyle where Self == ReadableSecondary {
    /// A lighter version of a text color for supporting details that still reads at 4.5:1 on its background.
    /// - Parameters:
    ///   - text: The primary text color.
    ///   - background: The color behind the text.
    /// - Returns: A style that resolves to the faded text color.
    static func readableSecondary(_ text: Color, on background: Color) -> ReadableSecondary {
        ReadableSecondary(text: text, background: background)
    }
}

nonisolated private extension ArtworkColor {
    /// Takes the sRGB components of a resolved color, without its opacity.
    /// - Parameter resolved: A color resolved for the current appearance.
    init(_ resolved: Color.Resolved) {
        self.init(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
    }
}
