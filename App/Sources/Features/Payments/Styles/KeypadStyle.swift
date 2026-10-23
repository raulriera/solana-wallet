import SwiftUI

/// How the payment keypad looks; the app supplies these defaults until a theme chooses others.
nonisolated struct KeypadStyle: Equatable, Sendable {
    /// What sits behind each digit key.
    nonisolated enum KeyBackground: Equatable, Sendable {
        /// Interactive Liquid Glass, as on the Phone keypad.
        case glass
        /// A solid circle in the key fill color.
        case filled
        /// Nothing; only the digit shows.
        case none
    }

    /// How the typed amount is drawn.
    nonisolated enum AmountLook: Equatable, Sendable {
        /// A brushed-metal gradient between the theme's primary and secondary text colors.
        case chrome
        /// The theme's primary text color.
        case plain
    }

    /// What sits behind each digit key.
    var keyBackground = KeyBackground.glass
    /// The color of the keys' digits and symbols.
    var keyText = PaletteRole.primaryText
    /// The color of filled key backgrounds.
    var keyFill = PaletteRole.surface
    /// How the typed amount is drawn.
    var amountLook = AmountLook.chrome
}

extension View {
    /// Draws the payment keypads in this view with the given options.
    /// - Parameter style: How the keys and the typed amount look.
    /// - Returns: The view with the keypad options set.
    func keypadStyle(_ style: KeypadStyle) -> some View {
        environment(\.keypadStyle, style)
    }
}
