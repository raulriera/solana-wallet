import Foundation
import Testing
@testable import widgets

struct QuantityFormatStyleTests {
    @Test(arguments: [
        ("0.083408632", 9, "en_US", "0.083408632 SOL"),
        ("5", 9, "en_US", "5 SOL"),
        ("1234.5", 9, "de_DE", "1.234,5 SOL"),
        ("0.123456789", 4, "en_US", "0.1234 SOL"),
    ])
    func `A quantity shows its digits and symbol`(quantity: String, decimals: Int, locale: String,
                                                    shown: String) throws {
        let value = try #require(Decimal(string: quantity))
        let style = QuantityFormatStyle(symbol: "SOL", decimals: decimals).locale(Locale(identifier: locale))
        #expect(value.formatted(style) == shown)
    }
}
