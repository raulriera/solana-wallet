import Foundation

/// Formats a typed amount in its unit as the person types it, as in $12, $12., or $12.50.
///
/// Typed fraction digits stay, including trailing zeros, and a trailing separator shows until the next digit.
nonisolated struct AmountEntryFormatStyle: FormatStyle {
    /// What the amount counts.
    nonisolated enum Unit: Codable, Hashable {
        /// A currency, by its ISO code.
        case currency(code: String)
        /// A token, by its symbol.
        case token(symbol: String)
    }

    let unit: Unit
    var locale: Locale = .autoupdatingCurrent

    /// Formats the typed digits with the locale's grouping, separator, and currency placement.
    /// - Parameter value: The typed amount.
    /// - Returns: The amount as the keypad shows it.
    func format(_ value: AmountEntry) -> String {
        let typed = value.fractionDigits?.count ?? 0
        // A trailing separator borrows one fraction digit's place, which is removed below.
        let length = value.fractionDigits == nil ? 0 : max(typed, 1)
        switch unit {
        case .currency(let code):
            let text = value.value.formatted(.currency(code: code).precision(.fractionLength(length)).locale(locale))
            return Self.removingPlaceholder(from: text, of: value)
        case .token(let symbol):
            let number = value.value.formatted(.number.precision(.fractionLength(length)).locale(locale))
            // The symbol joins after the placeholder is gone, so a symbol's own digits stay.
            return "\(Self.removingPlaceholder(from: number, of: value)) \(symbol)"
        }
    }

    /// Removes the digit that stands in after a trailing separator, wherever the currency symbol sits.
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

    /// Returns a copy that uses another locale.
    /// - Parameter locale: The locale for digits, separators, and currency placement.
    /// - Returns: The updated format style.
    func locale(_ locale: Locale) -> Self {
        var copy = self
        copy.locale = locale
        return copy
    }
}

nonisolated extension FormatStyle where Self == AmountEntryFormatStyle {
    /// A typed amount in a currency or token, as the keypad shows it.
    /// - Parameter unit: What the amount counts.
    /// - Returns: The format style.
    static func entry(in unit: AmountEntryFormatStyle.Unit) -> Self { Self(unit: unit) }
}

extension AmountEntry {
    /// Formats the typed amount with a format style, such as ``AmountEntryFormatStyle``.
    /// - Parameter style: The format style.
    /// - Returns: The formatted amount.
    nonisolated func formatted<Style: FormatStyle>(_ style: Style) -> Style.FormatOutput
    where Style.FormatInput == AmountEntry {
        style.format(self)
    }
}
