import Foundation
import Portfolio

/// Formats exact token quantities.
nonisolated struct AmountFormatStyle: FormatStyle {
    var locale: Locale = .autoupdatingCurrent
    /// Whether quantities from 10,000 up are shortened.
    var abbreviates = false

    func format(_ value: Amount) -> String {
        let quantity = Decimal(value)
        guard abbreviates, quantity >= .abbreviationThreshold else { return value.formatted(locale: locale) }
        return quantity.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(locale))
    }

    func locale(_ locale: Locale) -> Self {
        var copy = self
        copy.locale = locale
        return copy
    }
}

nonisolated extension FormatStyle where Self == AmountFormatStyle {
    static var amount: Self { Self() }

    /// A style that shortens token quantities from 10,000 up.
    static var abbreviatedAmount: Self { Self(abbreviates: true) }
}
