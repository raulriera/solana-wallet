import Foundation
import Testing
@testable import RPC

struct DecimalExchangeRateTests {
    @Test(arguments: [
        ("1.0", Decimal(1)),
        ("156.8", Decimal(sign: .plus, exponent: -1, significand: 1_568)),
        ("0.0000091", Decimal(sign: .plus, exponent: -7, significand: 91)),
    ])
    func `Positive decimal text is a rate`(text: String, rate: Decimal) {
        #expect(Decimal(exchangeRate: text) == rate)
    }

    @Test(arguments: ["0", "0.0", "-0.89", "soon", "", "NaN"])
    func `Text that isn't a positive number is not a rate`(text: String) {
        #expect(Decimal(exchangeRate: text) == nil)
    }

    @Test(arguments: ["1,5", "1.5abc", " 2", "2 ", "1e3", "+1.5", ".5", "5.", "1.2.3", "١.٥"])
    func `Text with anything besides plain decimal digits is not a rate`(text: String) {
        #expect(Decimal(exchangeRate: text) == nil)
    }
}
