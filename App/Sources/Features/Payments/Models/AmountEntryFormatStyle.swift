import Foundation

/// A format style that shows a typed amount in its unit as typed, as in $12, $12., or $12.50.
nonisolated struct AmountEntryFormatStyle: LocalizedFormatStyle {
    /// The unit of an amount.
    nonisolated enum Unit: Codable, Hashable {
        case currency(code: String)
        case token(symbol: String)
    }

    let unit: Unit
    var locale: Locale = .autoupdatingCurrent

    func format(_ value: AmountEntry) -> String {
        let length = value.fractionDigits?.count ?? 0
        let separator: NumberFormatStyleConfiguration.DecimalSeparatorDisplayStrategy =
            value.fractionDigits == nil ? .automatic : .always
        switch unit {
        case .currency(let code):
            return value.value.formatted(.currency(code: code).precision(.fractionLength(length))
                .decimalSeparator(strategy: separator).locale(locale))
        case .token(let symbol):
            let number = value.value.formatted(.number.precision(.fractionLength(length))
                .decimalSeparator(strategy: separator).locale(locale))
            return "\(number) \(symbol)"
        }
    }
}

nonisolated extension FormatStyle where Self == AmountEntryFormatStyle {
    /// Returns a style that formats a typed amount in a currency or token.
    ///
    /// - Parameter unit: The unit of the amount.
    /// - Returns: The format style.
    static func entry(in unit: AmountEntryFormatStyle.Unit) -> Self { Self(unit: unit) }
}

extension AmountEntry {
    /// Formats the typed amount with a format style, such as ``AmountEntryFormatStyle``.
    ///
    /// - Parameter style: The format style.
    /// - Returns: The formatted amount.
    nonisolated func formatted<Style: FormatStyle>(_ style: Style) -> Style.FormatOutput
    where Style.FormatInput == AmountEntry {
        style.format(self)
    }
}
