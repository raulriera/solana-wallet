import Foundation
import Transactions

/// Formats token quantities exactly or shortened from 10,000 up, with or without a symbol.
nonisolated struct TokenAmountFormatStyle: LocalizedFormatStyle {
    var locale: Locale = .autoupdatingCurrent
    /// Whether quantities from 10,000 up are shortened.
    var abbreviates = false
    /// The symbol to show after the quantity, as in 0.173768332 SOL, or `nil` for the quantity alone.
    var symbol: String?

    func format(_ value: TokenAmount) -> String {
        let quantity = Decimal(value)
        let digits = abbreviates && quantity >= .abbreviationThreshold
            ? quantity.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(locale))
            : exact(value)
        return symbol.map { "\(digits) \($0)" } ?? digits
    }

    /// Returns the exact quantity in whole asset units, without trailing fractional zeros.
    ///
    /// - Parameter value: The amount to format.
    /// - Returns: The quantity's localized digits.
    private func exact(_ value: TokenAmount) -> String {
        let digits = String(value.amount)
        let whole = UInt64(digits.dropLast(Int(value.decimals))) ?? 0
        var fraction = UInt64(digits.suffix(Int(value.decimals))) ?? 0
        let style = IntegerFormatStyle<UInt64>(locale: locale)

        guard fraction != 0 else { return style.format(whole) }

        var fractionLength = Int(value.decimals)
        while fraction.isMultiple(of: 10) {
            fraction /= 10
            fractionLength -= 1
        }

        return style.decimalSeparator(strategy: .always).format(whole)
            + style.grouping(.never).precision(.integerLength(fractionLength...)).format(fraction)
    }
}

nonisolated extension FormatStyle where Self == TokenAmountFormatStyle {
    static var amount: Self { Self() }

    /// A style that shortens token quantities from 10,000 up.
    static var abbreviatedAmount: Self { Self(abbreviates: true) }

    /// Returns a style that shows an amount of an asset with the asset's symbol.
    ///
    /// - Parameter asset: The asset the amount counts.
    /// - Returns: The format style.
    static func amount(of asset: Asset) -> Self { Self(symbol: asset.displaySymbol) }
}
