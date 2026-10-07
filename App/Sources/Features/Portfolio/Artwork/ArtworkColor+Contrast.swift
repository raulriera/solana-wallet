import SwiftUI

// Color math shared by card tints and readable secondary text, so both measure contrast the same way.
nonisolated extension ArtworkColor {
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
