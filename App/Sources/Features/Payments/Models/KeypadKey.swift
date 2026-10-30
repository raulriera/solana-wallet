import Foundation

/// A key on the payment keypad.
nonisolated enum KeypadKey: Hashable, Sendable {
    /// A digit from 0 to 9.
    case digit(Int)
    case decimalSeparator
    case delete

    /// Creates the key that a hardware keyboard's characters type, or `nil` when they aren't a digit or a separator.
    ///
    /// - Parameters:
    ///   - characters: The characters the key press produced.
    ///   - locale: The locale whose decimal separator the keypad types.
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
