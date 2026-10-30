import Foundation
import Testing
@testable import widgets

@MainActor
struct KeypadPaymentTests {
    private static let sol = PaymentToken(mint: nil, symbol: "SOL", balance: 2, price: nil, decimals: 9)

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
