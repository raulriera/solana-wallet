import Foundation

/// Formats a token's value or price in its quote currency.
nonisolated struct ValueFormatStyle: FormatStyle {
    /// The quote currency's ISO code, such as `USD`.
    let code: String
    /// Whether values from 10,000 up are shortened.
    var abbreviates = false
    /// Whether amounts below 1 keep their significant digits.
    var isPrice = false
    var locale: Locale = .autoupdatingCurrent

    func format(_ value: Decimal) -> String {
        let full = Decimal.FormatStyle.Currency(code: code, locale: locale)
        if abbreviates, value.magnitude >= .abbreviationThreshold {
            return value.formatted(full.notation(.compactName).precision(.fractionLength(0...1)))
        }
        guard isPrice, value != 0, value.magnitude < 1 else { return value.formatted(full) }
        return value.formatted(full.precision(value.magnitude < 0.01 ? .significantDigits(1...4) : .fractionLength(2...4)))
    }

    func locale(_ locale: Locale) -> Self {
        var copy = self
        copy.locale = locale
        return copy
    }
}

nonisolated extension FormatStyle where Self == ValueFormatStyle {
    /// Returns a style that formats a token's value in full.
    ///
    /// - Parameter code: The quote currency's ISO code.
    /// - Returns: The format style.
    static func value(code: String) -> Self { Self(code: code) }

    /// Returns a style that shortens a token's value from 10,000 up.
    ///
    /// - Parameter code: The quote currency's ISO code.
    /// - Returns: The format style.
    static func abbreviatedValue(code: String) -> Self { Self(code: code, abbreviates: true) }

    /// Returns a style that formats the price of one token.
    ///
    /// - Parameter code: The quote currency's ISO code.
    /// - Returns: The format style.
    static func price(code: String) -> Self { Self(code: code, isPrice: true) }
}
