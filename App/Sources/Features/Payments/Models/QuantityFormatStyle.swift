import Foundation

/// A format style that shows a token quantity with all of its decimals and its symbol, as in 0.173768332 SOL.
nonisolated struct QuantityFormatStyle: FormatStyle {
    let symbol: String
    let decimals: Int
    var locale: Locale = .autoupdatingCurrent

    func format(_ value: Decimal) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...decimals)).rounded(rule: .towardZero).locale(locale))) \(symbol)"
    }

    func locale(_ locale: Locale) -> Self {
        var copy = self
        copy.locale = locale
        return copy
    }
}

nonisolated extension FormatStyle where Self == QuantityFormatStyle {
    /// Returns a style that formats a quantity of a token.
    ///
    /// - Parameter token: The token the quantity counts.
    /// - Returns: The format style.
    static func quantity(of token: PaymentToken) -> Self { Self(symbol: token.symbol, decimals: token.decimals) }
}
