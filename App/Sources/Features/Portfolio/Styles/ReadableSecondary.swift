import SwiftUI

/// A lighter version of a text color for supporting details that still reads at 4.5:1 on its background.
nonisolated struct ReadableSecondary: ShapeStyle {
    let text: Color
    let background: Color

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        let target = environment.colorSchemeContrast == .increased ? 7.0 : 4.6
        return Self.faded(text.resolve(in: environment), on: background.resolve(in: environment), toContrast: target)
    }

    /// Fades a text color toward its background until one more step would read below the target contrast.
    ///
    /// - Parameters:
    ///   - text: The resolved text color.
    ///   - background: The resolved background color.
    ///   - target: The lowest contrast ratio the faded color may have.
    /// - Returns: An opaque color at the target contrast or more.
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
    /// Returns a lighter version of a text color that still reads at 4.5:1 on a background.
    ///
    /// - Parameters:
    ///   - text: The primary text color.
    ///   - background: The color behind the text.
    /// - Returns: A style that resolves to the faded text color.
    static func readableSecondary(_ text: Color, on background: Color) -> ReadableSecondary {
        ReadableSecondary(text: text, background: background)
    }
}

nonisolated private extension ArtworkColor {
    /// Creates a color from the sRGB components of a resolved color.
    ///
    /// - Parameter resolved: A color resolved for the current appearance.
    init(_ resolved: Color.Resolved) {
        self.init(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
    }
}
