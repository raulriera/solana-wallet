import Foundation
import Portfolio
import Testing

/// Tests exact quantity formatting through the framework's public API.
struct AmountTests {
    /// Verifies decimal placement without rounding, trailing zeros, or lost units.
    ///
    /// - Parameters:
    ///   - amount: The raw quantity to display.
    ///   - expected: Its exact representation in the US English locale.
    @Test(arguments: [
        (Amount(units: 1_250_000_000, decimals: 9), "1.25"),
        (Amount(units: 1_000_000_000, decimals: 9), "1"),
        (Amount(units: 1, decimals: 9), "0.000000001"),
        (Amount(units: 0, decimals: 9), "0"),
        (Amount(units: .max, decimals: 0), "18,446,744,073,709,551,615"),
        (Amount(units: .max, decimals: 6), "18,446,744,073,709.551615"),
        (Amount(units: .max, decimals: 20), "0.18446744073709551615"),
        (Amount(units: 1, decimals: .max), "0." + String(repeating: "0", count: 254) + "1"),
    ])
    func `Amounts display exact asset quantities without trailing fractional zeros`(amount: Amount, expected: String) {
        #expect(amount.formatted(locale: Locale(identifier: "en_US")) == expected)
    }

    /// Verifies grouping, fractional padding, separators, and localized digits.
    ///
    /// - Parameters:
    ///   - identifier: The locale used to display the quantity.
    ///   - expected: The localized representation of the quantity.
    @Test(arguments: [
        ("en_US", "1,234.0005"),
        ("de_DE", "1.234,0005"),
        ("ar_EG", "١٬٢٣٤٫٠٠٠٥"),
    ])
    func `Amounts use the locale's grouping separators and digits`(identifier: String, expected: String) {
        let amount = Amount(units: 12_340_005, decimals: 4)

        #expect(amount.formatted(locale: Locale(identifier: identifier)) == expected)
    }
}
