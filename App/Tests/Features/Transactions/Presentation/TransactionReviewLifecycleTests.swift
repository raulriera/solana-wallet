import Foundation
@testable import RPC
import SwiftUI
import Testing
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
        let error = TransactionError(name: "InsufficientFundsForFee", details: nil)
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

    @Test
    func `A stopped watch shows no alert and settles later`() async throws {
        let refusal = RPCError.http(statusCode: 429, retryAfter: "3")
        let sockets = SocketSequence { $0 == 0 ? SocketSequence.failing(with: refusal) : SocketSequence.watch() }
        let payment = try LocalPaymentReview(statuses: [.status(.finalized)], sockets: sockets)
        try await payment.model.runReview()
        let hosted = try HostedWindow(NavigationStack {
            TransactionReviewScreen<PaymentReviewScreen, PaymentResultScreen>(review: payment.model)
        })
        defer { hosted.close() }
        try #require(try await hosted.appears())

        payment.model.approve()
        for await record in Observations({ payment.model.record }) where record != nil { break }
        let record = try #require(payment.model.record)
        await #expect(throws: (any Error).self) {
            try await payment.transactions.watch(record.id, for: record.key)
        }

        #expect(try await !hosted.presentsViewController(within: .seconds(1)))
        #expect(payment.model.isSending)

        await payment.transactions.resume()

        #expect(await payment.transactions.settledStatus(of: record) == .succeeded)
        #expect(payment.model.outcome == .succeeded)
        #expect(hosted.host.presentedViewController == nil)
        await sockets.waitUntilClosed()
    }
}
