import Foundation
import Testing
@testable import widgets

/// Checks which hardware keyboard characters type on the payment keypad.
struct KeypadKeyTests {
    /// Digits from any script type themselves, but not other numerals such as superscripts, and the locale's
    /// separator and a period type the decimal separator.
    /// - Parameters:
    ///   - characters: The characters a key press produced.
    ///   - locale: The locale's identifier.
    ///   - key: The keypad key they type, if any.
    @Test(arguments: [
        ("5", "en_US", KeypadKey.digit(5)),
        (".", "en_US", .decimalSeparator),
        (",", "de_DE", .decimalSeparator),
        (".", "de_DE", .decimalSeparator),
        (",", "fr_FR", .decimalSeparator),
        (",", "en_US", nil),
        ("a", "en_US", nil),
        ("12", "en_US", nil),
        ("\u{0665}", "ar", .digit(5)),
        ("\u{066B}", "ar@numbers=arab", .decimalSeparator),
        ("\u{00B2}", "en_US", nil),
    ])
    func `Hardware keys type keypad keys`(characters: String, locale: String, key: KeypadKey?) {
        #expect(KeypadKey(typing: characters, locale: Locale(identifier: locale)) == key)
    }
}
