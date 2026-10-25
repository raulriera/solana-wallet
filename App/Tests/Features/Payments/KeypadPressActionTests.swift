import Foundation
import Testing
@testable import widgets

/// Checks that the keypad press action types each key into the payment's amount.
@MainActor
struct KeypadPressActionTests {
    /// A dollar stablecoin, so the amount is typed in tokens without conversion.
    private static let usdc = PaymentToken(mint: PaymentFixtures.usdc, symbol: "USDC", balance: 40, price: 1,
                                           decimals: 6)

    /// Pressing digits types them into the amount.
    @Test func `Pressing keys types the amount`() {
        let payment = PaymentModel(tokens: [Self.usdc], currencyCode: "USD")
        let pressKey = KeypadPressAction(payment: payment)

        pressKey(.digit(1))
        pressKey(.digit(2))

        #expect(payment.quantity == 12)
        #expect(payment.pressCount == 2)
    }
}
