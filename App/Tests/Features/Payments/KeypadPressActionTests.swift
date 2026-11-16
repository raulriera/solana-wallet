import Foundation
import Testing
import Transactions
@testable import widgets

@MainActor
struct KeypadPressActionTests {
    private static let usdc = PaymentToken(
        asset: .token(.fixture(PaymentFixtures.usdc.value, decimals: 6, symbol: "USDC")),
        balance: TokenAmount(amount: 40_000_000, decimals: 6), price: 1)

    @Test func `Pressing keys types the amount`() {
        let payment = PaymentModel(tokens: [Self.usdc], currencyCode: "USD")
        let pressKey = KeypadPressAction(payment: payment)

        pressKey(.digit(1))
        pressKey(.digit(2))

        #expect(payment.quantity == 12)
        #expect(payment.pressCount == 2)
    }
}
