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
        let typed = value.fractionDigits?.count ?? 0
        let length = value.fractionDigits == nil ? 0 : max(typed, 1)
        switch unit {
        case .currency(let code):
            let text = value.value.formatted(.currency(code: code).precision(.fractionLength(length)).locale(locale))
            return Self.removingPlaceholder(from: text, of: value)
        case .token(let symbol):
            let number = value.value.formatted(.number.precision(.fractionLength(length)).locale(locale))
            return "\(Self.removingPlaceholder(from: number, of: value)) \(symbol)"
        }
    }

    /// Removes the placeholder digit after a trailing separator.
    ///
    /// - Parameters:
    ///   - text: The formatted amount.
    ///   - value: The typed amount.
    /// - Returns: The text without the placeholder, or unchanged when the amount doesn't end in a separator.
    private static func removingPlaceholder(from text: String, of value: AmountEntry) -> String {
        guard value.fractionDigits?.isEmpty == true, let placeholder = text.lastIndex(where: \.isNumber) else {
            return text
        }
        var text = text
        text.remove(at: placeholder)
        return text
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
