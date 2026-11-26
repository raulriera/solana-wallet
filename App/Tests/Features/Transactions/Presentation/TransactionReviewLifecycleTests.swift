import Foundation
import SwiftUI
import Testing
@testable import RPC
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TransactionReviewLifecycleTests {
    @Test
    func `Showing the review simulates it`() async throws {
        let payment = try LocalPaymentReview()
        payment.model.prepareReview()
        let hosted = try HostedWindow(NavigationStack {
            TransactionReviewScreen<PaymentReviewScreen, PaymentResultScreen>(review: payment.model)
        })
        defer { hosted.close() }
        try #require(try await hosted.appears())

        for await canApprove in Observations({ payment.model.canApprove }) where canApprove { break }
        #expect(payment.model.review == LocalPaymentReview.costs)
    }

    @Test
    func `A failed review shows its alert`() async throws {
        let error = TransactionError.insufficientFundsForFee
        let payment = try LocalPaymentReview(simulation: .failure(error, fee: LocalPaymentReview.networkFee))
        payment.model.prepareReview()
        let hosted = try HostedWindow(NavigationStack {
            TransactionReviewScreen<PaymentReviewScreen, PaymentResultScreen>(review: payment.model)
        })
        defer { hosted.close() }
        try #require(try await hosted.appears())

        #expect(try await hosted.presentsViewController())
        #expect(payment.model.error == .notEnoughSOL)
    }
}
