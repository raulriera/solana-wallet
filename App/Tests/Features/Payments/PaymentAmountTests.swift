import Foundation
import Testing
@testable import widgets

struct PaymentAmountTests {
    @Test(arguments: [
        (Decimal(string: "1.5")!, 9, UInt64(1_500_000_000)),
        (Decimal(string: "0.000000001")!, 9, 1),
        (Decimal(string: "12.345678")!, 6, 12_345_678),
    ])
    func `A quantity counts in the token's smallest units`(quantity: Decimal, decimals: Int, units: UInt64) {
        let token = PaymentToken(mint: nil, symbol: "TOKEN", balance: 100, price: nil, decimals: decimals)

        #expect(PaymentAmount(token: token, quantity: quantity, value: nil, currencyCode: "USD").units == units)
    }
}
