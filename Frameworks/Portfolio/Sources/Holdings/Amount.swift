public import Foundation

/// An exact quantity expressed in integer units and decimal places.
public struct Amount: Codable, Sendable, Equatable {
    /// The quantity in the asset's smallest units.
    public let units: UInt64
    /// The number of decimal places used by the asset.
    public let decimals: UInt8

    /// Creates a quantity without floating-point conversion.
    ///
    /// - Parameters:
    ///   - units: The exact integer quantity.
    ///   - decimals: The number of decimal places.
    public init(units: UInt64, decimals: UInt8) {
        self.units = units
        self.decimals = decimals
    }

    /// Returns a localized string representing the quantity in whole asset units.
    ///
    /// The result preserves every nonzero fractional digit and omits trailing
    /// fractional zeros. It uses the locale's digits, grouping, and decimal
    /// separator, without adding a token symbol or converting to floating point.
    /// For example, 1,250,000,000 units with nine decimal places becomes `1.25`
    /// in the `en_US` locale.
    ///
    /// - Parameter locale: The locale used to format the quantity.
    /// - Returns: The exact quantity formatted for display.
    public func formatted(locale: Locale) -> String {
        let digits = String(units)
        let whole = UInt64(digits.dropLast(Int(decimals))) ?? 0
        var fraction = UInt64(digits.suffix(Int(decimals))) ?? 0
        let style = IntegerFormatStyle<UInt64>(locale: locale)

        guard fraction != 0 else { return style.format(whole) }

        var fractionLength = Int(decimals)
        while fraction.isMultiple(of: 10) {
            fraction /= 10
            fractionLength -= 1
        }

        return style.decimalSeparator(strategy: .always).format(whole)
            + style.grouping(.never).precision(.integerLength(fractionLength...)).format(fraction)
    }
}
