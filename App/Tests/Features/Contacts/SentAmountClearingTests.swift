import Foundation
import Observation
import RPC
import Testing
import Transactions
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SentAmountClearingTests {
    @Test
    func `The amount clears on success after the review closed mid-send`() async throws {
        let sending = try Sending()
        let hosted = try HostedWindow(SentAmountClearingRoot(payment: sending.keypad, kept: sending.kept))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        let send = try await sending.approveAndClose()
        await sending.deliver(send)

        for await quantity in Observations({ sending.keypad.quantity }) where quantity == 0 { break }
        #expect(sending.payment.model.outcome == .succeeded)
        #expect(sending.kept.review == nil)
        await sending.payment.sockets.waitUntilClosed()
    }

    @Test
    func `A payment that succeeded meanwhile clears the amount when it appears`() async throws {
        let sending = try Sending()
        let send = try await sending.approveAndClose()
        await sending.deliver(send)
        let record = try #require(sending.payment.model.record)
        #expect(await sending.payment.transactions.outcome(of: record) == .succeeded)
        #expect(sending.keypad.quantity == 1)

        let hosted = try HostedWindow(SentAmountClearingRoot(payment: sending.keypad, kept: sending.kept))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        for await quantity in Observations({ sending.keypad.quantity }) where quantity == 0 { break }
        await sending.payment.sockets.waitUntilClosed()
    }

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
        #expect(await sending.payment.transactions.outcome(of: record) == .succeeded)
        #expect(sending.keypad.quantity == 15)
        await sending.payment.sockets.waitUntilClosed()
    }

    @MainActor
    private struct Sending {
        let payment: LocalPaymentReview
        let keypad = PaymentModel(tokens: [PaymentFixtures.sol], currencyCode: "USD")
        let kept = KeptPaymentReview()
        let gate = Suspension()

        init() throws {
            payment = try LocalPaymentReview(statuses: [.status(.finalized)], sent: .sending(gate: gate))
            keypad.press(.digit(1))
            kept.review = payment.model
        }

        func approveAndClose() async throws -> Task<Void, Never> {
            try await payment.model.runReview()
            let model = payment.model
            model.approve()
            let attempt = model.attempt
            let task = Task { await model.run(attempt) }
            await gate.waitUntilStarted()
            task.cancel()
            return task
        }

        func deliver(_ send: Task<Void, Never>) async {
            gate.resume()
            await send.value
        }
    }
}
