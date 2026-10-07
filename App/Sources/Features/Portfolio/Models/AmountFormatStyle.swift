import Foundation
import Portfolio

/// Formats exact token quantities with the locale that SwiftUI's text environment supplies.
///
/// The abbreviated form shortens quantities from 10,000 up to one decimal, as in 11M, for cards and rows.
nonisolated struct AmountFormatStyle: FormatStyle {
    var locale: Locale = .autoupdatingCurrent
    /// Whether quantities from 10,000 up are shortened.
    var abbreviates = false

    /// Formats every significant digit without floating-point conversion, or a shortened large quantity.
    /// - Parameter value: The exact token quantity.
    /// - Returns: A localized quantity without a token symbol.
    func format(_ value: Amount) -> String {
        let quantity = Decimal(sign: .plus, exponent: -Int(value.decimals), significand: Decimal(value.units))
        guard abbreviates, quantity >= .abbreviationThreshold else { return value.formatted(locale: locale) }
        return quantity.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(locale))
    }

    /// Returns a copy that uses another locale.
    /// - Parameter locale: The locale for digits and separators.
    /// - Returns: The updated format style.
    func locale(_ locale: Locale) -> Self {
        var copy = self
        copy.locale = locale
        return copy
    }
}

nonisolated extension FormatStyle where Self == AmountFormatStyle {
    /// Exact, localized token quantities.
    static var amount: Self { Self() }

    /// Token quantities shortened from 10,000 up for cards and rows.
    static var abbreviatedAmount: Self { Self(abbreviates: true) }
}
