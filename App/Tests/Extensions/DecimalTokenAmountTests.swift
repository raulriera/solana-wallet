import Foundation
import Testing
import Transactions
@testable import widgets

struct DecimalTokenAmountTests {
    @Test(arguments: [
        (TokenAmount(amount: 1_500_000_000, decimals: 9), Decimal(string: "1.5")!),
        (TokenAmount(amount: 1, decimals: 6), Decimal(string: "0.000001")!),
        (TokenAmount(amount: 42, decimals: 0), Decimal(42)),
        (TokenAmount(amount: 0, decimals: 9), Decimal(0)),
        (TokenAmount(amount: .max, decimals: 9), Decimal(string: "18446744073.709551615")!),
    ])
    func `Units become a quantity at the amount's decimals`(balance: TokenAmount, expected: Decimal) {
        #expect(Decimal(balance) == expected)
    }
}
