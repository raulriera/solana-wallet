import Foundation
import Testing
@testable import widgets

/// Names what the contacts tab's keypad pays with.
@MainActor
struct KeypadPaymentTests {
    private static let sol = PaymentToken(mint: nil, symbol: "SOL", balance: 2, price: nil, decimals: 9)

    /// Only a ready keypad has a payment, and only a loading one waits.
    @Test func `Each state reports its payment and whether it's loading`() {
        let model = PaymentModel(tokens: [Self.sol], currencyCode: "USD")

        #expect(KeypadPayment.loading.model == nil)
        #expect(KeypadPayment.loading.isLoading)
        #expect(KeypadPayment.nothingToSend.model == nil)
        #expect(!KeypadPayment.nothingToSend.isLoading)
        #expect(KeypadPayment.ready(model).model === model)
        #expect(!KeypadPayment.ready(model).isLoading)
    }
}
