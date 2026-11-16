import Foundation
import Testing
import Transactions
@testable import widgets

@MainActor
struct KeypadPaymentTests {
    @Test func `Each state reports its payment and whether it's loading`() {
        let model = PaymentModel(tokens: [PaymentFixtures.sol], currencyCode: "USD")

        #expect(KeypadPayment.loading.model == nil)
        #expect(KeypadPayment.loading.isLoading)
        #expect(KeypadPayment.nothingToSend.model == nil)
        #expect(!KeypadPayment.nothingToSend.isLoading)
        #expect(KeypadPayment.ready(model).model === model)
        #expect(!KeypadPayment.ready(model).isLoading)
    }
}
