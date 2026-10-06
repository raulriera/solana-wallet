import Foundation
import Portfolio

/// Formats exact token quantities with the locale that SwiftUI's text environment supplies.
nonisolated struct AmountFormatStyle: FormatStyle {
    var locale: Locale = .autoupdatingCurrent

    /// Formats every significant digit without floating-point conversion.
    /// - Parameter value: The exact token quantity.
    /// - Returns: A localized quantity without a token symbol.
    func format(_ value: Amount) -> String {
        value.formatted(locale: locale)
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

extension FormatStyle where Self == AmountFormatStyle {
    /// Exact, localized token quantities.
    static var amount: Self { Self() }
}
