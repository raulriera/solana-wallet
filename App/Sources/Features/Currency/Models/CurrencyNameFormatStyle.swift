import Foundation

/// A format style that shows a currency's name from its ISO code, as in Euro for `EUR`, or the code when it has no name.
nonisolated struct CurrencyNameFormatStyle: FormatStyle {
    var locale: Locale = .autoupdatingCurrent

    func format(_ code: String) -> String {
        locale.localizedString(forCurrencyCode: code) ?? code
    }

    func locale(_ locale: Locale) -> Self {
        var copy = self
        copy.locale = locale
        return copy
    }
}

nonisolated extension FormatStyle where Self == CurrencyNameFormatStyle {
    static var currencyName: Self { Self() }
}
