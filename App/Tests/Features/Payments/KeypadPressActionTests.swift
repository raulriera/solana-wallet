import Foundation
import Testing
@testable import widgets

@MainActor
struct KeypadPressActionTests {
    private static let usdc = PaymentToken(mint: PaymentFixtures.usdc, symbol: "USDC", balance: 40, price: 1,
                                           decimals: 6)

    @Test func `Pressing keys types the amount`() {
        let payment = PaymentModel(tokens: [Self.usdc], currencyCode: "USD")
        let pressKey = KeypadPressAction(payment: payment)

        pressKey(.digit(1))
        pressKey(.digit(2))

        #expect(payment.quantity == 12)
        #expect(payment.pressCount == 2)
    }
}
