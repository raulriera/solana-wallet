import SwiftUI
import Themes

/// The look of the payment keypad.
nonisolated struct KeypadStyle: Equatable, Sendable {
    /// The background of each digit key.
    nonisolated enum KeyBackground: Equatable, Sendable {
        case glass
        /// A solid circle in the key fill color.
        case filled
        case none
    }

    /// The look of the typed amount.
    nonisolated enum AmountLook: Equatable, Sendable {
        /// A metallic gradient between the primary and secondary text colors.
        case chrome
        /// The primary text color.
        case plain
    }

    var keyBackground = KeyBackground.glass
    /// The color of filled key backgrounds.
    var keyFill = Palette.Role.surface
    var amountLook = AmountLook.chrome
}

extension View {
    /// Sets the style of the payment keypads in this view.
    ///
    /// - Parameter style: The keypad style.
    /// - Returns: The view with the keypad style.
    func keypadStyle(_ style: KeypadStyle) -> some View {
        environment(\.keypadStyle, style)
    }
}
