import Foundation

/// Formats a token's value or price in its quote currency.
///
/// Values can shorten from 10,000 up to one decimal in the locale's own short form, as in US$10.2K, so cards
/// and rows fit their columns; the detail screen and VoiceOver use the full value. Prices below 1 keep their
/// significant digits, as in US$0.4056 or US$0.000021.
nonisolated struct ValueFormatStyle: FormatStyle {
    /// The quote currency's ISO code, such as `USD`.
    let code: String
    /// Whether values from 10,000 up are shortened.
    var abbreviates = false
    /// Whether amounts below 1 keep their significant digits, as a price of one token does.
    var isPrice = false
    var locale: Locale = .autoupdatingCurrent

    /// Formats the amount in full, shortened when it's large and the style abbreviates, or with more
    /// digits when it's a small price.
    /// - Parameter value: The token's total value or price.
    /// - Returns: A localized currency amount.
    func format(_ value: Decimal) -> String {
        let full = Decimal.FormatStyle.Currency(code: code, locale: locale)
        if abbreviates, value.magnitude >= .abbreviationThreshold {
            return value.formatted(full.notation(.compactName).precision(.fractionLength(0...1)))
        }
        guard isPrice, value != 0, value.magnitude < 1 else { return value.formatted(full) }
        // Cents can't show a price like 0.000021; four significant digits can.
        return value.formatted(full.precision(value.magnitude < 0.01 ? .significantDigits(1...4) : .fractionLength(2...4)))
    }

    /// Returns a copy that uses another locale.
    /// - Parameter locale: The locale for digits, separators, and short forms.
    /// - Returns: The updated format style.
    func locale(_ locale: Locale) -> Self {
        var copy = self
        copy.locale = locale
        return copy
    }
}

nonisolated extension FormatStyle where Self == ValueFormatStyle {
    /// A token's value in full.
    /// - Parameter code: The quote currency's ISO code.
    /// - Returns: The format style.
    static func value(code: String) -> Self { Self(code: code) }

    /// A token's value, shortened from 10,000 up for cards and rows.
    /// - Parameter code: The quote currency's ISO code.
    /// - Returns: The format style.
    static func abbreviatedValue(code: String) -> Self { Self(code: code, abbreviates: true) }

    /// The price of one token, with enough digits to show a price below one cent.
    /// - Parameter code: The quote currency's ISO code.
    /// - Returns: The format style.
    static func price(code: String) -> Self { Self(code: code, isPrice: true) }
}

extension Decimal {
    /// Values and balances from this size up are shortened on cards and rows, where full digits crowd out the name.
    nonisolated static let abbreviationThreshold: Decimal = 10_000
}
