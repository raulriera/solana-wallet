import Foundation
import Portfolio
import Testing
@testable import widgets

struct DecimalAmountTests {
    @Test(arguments: [
        (Amount(units: 1_500_000_000, decimals: 9), Decimal(string: "1.5")!),
        (Amount(units: 1, decimals: 6), Decimal(string: "0.000001")!),
        (Amount(units: 42, decimals: 0), Decimal(42)),
        (Amount(units: 0, decimals: 9), Decimal(0)),
        (Amount(units: .max, decimals: 9), Decimal(string: "18446744073.709551615")!),
    ])
    func `Units become a quantity at the amount's decimals`(amount: Amount, expected: Decimal) {
        #expect(Decimal(amount) == expected)
    }
}
