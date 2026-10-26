import Foundation
import Observation
import RPC
import Testing
@testable import widgets

/// Follows a sent payment's review in a real window, so the keypad's amount clears once the payment succeeds.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SentAmountClearingTests {
    /// The account's SOL, without a price, so the keypad types SOL.
    private static let sol = PaymentToken(mint: nil, symbol: "SOL", balance: 2, price: nil, decimals: 9)

    /// A payment whose review closed while it was sent still clears the amount once it succeeds.
    /// - Throws: A test prerequisite error.
    @Test
    func `The amount clears on success after the review closed mid-send`() async throws {
        let sending = try Sending()
        let hosted = try HostedWindow(SentAmountClearingRoot(payment: sending.keypad, kept: sending.kept))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        let send = try await sending.approveAndClose()
        await sending.deliver(send)

        // The suite's time limit ends the wait if the amount never clears.
        for await quantity in Observations({ sending.keypad.quantity }) where quantity == 0 { break }
        #expect(sending.payment.model.outcome == .succeeded)
        // The amount clears once, so a later appearance never clears a newly typed amount.
        #expect(sending.kept.review == nil)
        await sending.payment.sockets.waitUntilClosed()
    }

    /// A payment that succeeded while the keypad wasn't shown clears the amount when it appears, as when the tab
    /// returns.
    /// - Throws: A test prerequisite error.
    @Test
    func `A payment that succeeded meanwhile clears the amount when it appears`() async throws {
        let sending = try Sending()
        let send = try await sending.approveAndClose()
        await sending.deliver(send)
        let record = try #require(sending.payment.model.record)
        #expect(await sending.payment.transactions.settledStatus(of: record) == .succeeded)
        #expect(sending.keypad.quantity == 1)

        let hosted = try HostedWindow(SentAmountClearingRoot(payment: sending.keypad, kept: sending.kept))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        // The suite's time limit ends the wait if the amount never clears.
        for await quantity in Observations({ sending.keypad.quantity }) where quantity == 0 { break }
        await sending.payment.sockets.waitUntilClosed()
    }

    /// An amount typed after the review closed isn't the one that was sent, so it stays once the payment succeeds.
    /// - Throws: A test prerequisite error.
    @Test
    func `A newly typed amount stays when the sent payment succeeds`() async throws {
        let sending = try Sending()
        let hosted = try HostedWindow(SentAmountClearingRoot(payment: sending.keypad, kept: sending.kept))
        defer { hosted.close() }
        try #require(try await hosted.appears())
        let send = try await sending.approveAndClose()

        sending.keypad.press(.digit(5))
        for await review in Observations({ sending.kept.review }) where review == nil { break }
        await sending.deliver(send)

        let record = try #require(sending.payment.model.record)
        #expect(await sending.payment.transactions.settledStatus(of: record) == .succeeded)
        #expect(sending.keypad.quantity == 15)
        await sending.payment.sockets.waitUntilClosed()
    }

    /// A payment of the 1 SOL typed on a keypad, whose review the contacts tab keeps and whose send waits until the test
    /// delivers it.
    @MainActor
    private struct Sending {
        /// The payment's review.
        let payment: LocalPaymentReview
        /// The keypad's payment, with 1 SOL typed.
        let keypad = PaymentModel(tokens: [sol], currencyCode: "USD")
        /// The latest review, which the contacts tab keeps.
        let kept = KeptPaymentReview()
        /// Holds the send until the test delivers it.
        let gate = Suspension()

        /// Types 1 SOL and keeps its payment's review.
        /// - Throws: A fixture error.
        init() throws {
            payment = try LocalPaymentReview(statuses: [.status(.finalized)], sent: .sending(gate: gate))
            keypad.press(.digit(1))
            kept.review = payment.model
        }

        /// Reviews and approves the payment, then closes the review while it's sent, which cancels the review's task.
        /// - Returns: The review's cancelled task, which finishes once the payment is delivered.
        /// - Throws: A test failure when the review can't be approved.
        func approveAndClose() async throws -> Task<Void, Never> {
            try await payment.review()
            let model = payment.model
            model.approve()
            let attempt = model.attempt
            let task = Task { await model.run(attempt) }
            await gate.waitUntilStarted()
            task.cancel()
            return task
        }

        /// Delivers the held payment and waits until the review's task records it.
        /// - Parameter send: The review's cancelled task.
        func deliver(_ send: Task<Void, Never>) async {
            gate.resume()
            await send.value
        }
    }
}
