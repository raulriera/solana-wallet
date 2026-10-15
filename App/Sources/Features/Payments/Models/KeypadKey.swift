import Foundation

/// A key on the payment keypad.
nonisolated enum KeypadKey: Hashable, Sendable {
    /// A digit from 0 to 9.
    case digit(Int)
    /// The locale's decimal separator.
    case decimalSeparator
    /// Removes the last typed character.
    case delete

    /// The keypad key a character from a hardware keyboard types.
    ///
    /// A period types the separator in every locale, as on a number pad, besides the locale's own separator. Digits
    /// from any script type themselves, such as Arabic-Indic digits.
    /// - Parameters:
    ///   - characters: The characters the key press produced.
    ///   - locale: The locale whose decimal separator the keypad types.
    /// - Returns: The key, or `nil` when the characters aren't a digit or a separator.
    init?(typing characters: String, locale: Locale) {
        if characters == locale.decimalSeparator || characters == "." {
            self = .decimalSeparator
        } else if characters.unicodeScalars.count == 1, let scalar = characters.unicodeScalars.first,
                  scalar.properties.numericType == .decimal, let value = scalar.properties.numericValue {
            self = .digit(Int(value))
        } else {
            return nil
        }
    }
}
