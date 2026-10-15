import Foundation

/// Formats a token quantity with every decimal the token has, then its symbol, as in 0.173768332 SOL, so a quantity
/// never shows more than leaves.
nonisolated struct QuantityFormatStyle: FormatStyle {
    /// The token's symbol, such as SOL.
    let symbol: String
    /// The number of decimal places the token uses.
    let decimals: Int
    var locale: Locale = .autoupdatingCurrent

    /// Formats the quantity's digits, without trailing zeros and with extra digits dropped, followed by the symbol.
    /// - Parameter value: The token quantity.
    /// - Returns: The quantity and symbol.
    func format(_ value: Decimal) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...decimals)).rounded(rule: .towardZero).locale(locale))) \(symbol)"
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

nonisolated extension FormatStyle where Self == QuantityFormatStyle {
    /// A quantity of a token, with all of its decimals and its symbol.
    /// - Parameter token: The token the quantity counts.
    /// - Returns: The format style.
    static func quantity(of token: PaymentToken) -> Self { Self(symbol: token.symbol, decimals: token.decimals) }
}
