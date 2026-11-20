import Foundation
import Testing
import Transactions
@testable import RPC
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TransactionReviewModelTests {
    private static let rateLimit = RPCError.http(statusCode: 429, retryAfter: "3")

    @Test
    func `Reviewing shows the review`() async throws {
        let model = try LocalPaymentReview().model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.review == LocalPaymentReview.costs)
        #expect(model.canApprove)
        #expect(model.error == nil)
        #expect(model.attempt == nil)
    }

    @Test
    func `A failed simulation shows the proposal's error without a review`() async throws {
        let error = TransactionError(name: "InsufficientFundsForFee", details: nil)
        let model = try LocalPaymentReview(simulation: .failure(error, fee: LocalPaymentReview.networkFee)).model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.error == .notEnoughSOL)
        #expect(model.review == nil)
        #expect(!model.canApprove)
    }

    @Test
    func `Another error is a preparation failure that retrying reviews again`() async throws {
        let payment = try LocalPaymentReview()
        let limited = HTTPResponses([:], error: Self.rateLimit)
        let transactions = TransactionStore.inMemory { network in
            try TransactionCoordinator(rpc: SolanaRPC(network: network, transport: limited),
                                       store: UnavailableRecoveryStore())
        }
        let model = try TransactionReviewModel(payment.model.proposal, from: payment.account, on: .devnet,
                                               transactions: transactions)

        model.prepareReview()
        await model.run(model.attempt)
        try #require(model.error == .preparationFailed)

        model.retry()

        #expect(model.attempt?.work == .review)
        #expect(model.error == nil)
    }

    @Test
    func `A landed transaction shows its outcome from its record`() async throws {
        let payment = try LocalPaymentReview(statuses: [.status(.finalized)])
        let model = payment.model
        try await payment.model.runReview()

        model.approve()
        await model.run(model.attempt)
        let record = try #require(model.record)
        #expect(record.kind == .payment)
        #expect(model.submission?.network == .devnet)

        #expect(await payment.transactions.outcome(of: record) == .succeeded)
        #expect(model.outcome == .succeeded)
        #expect(!model.isSending)
        #expect(!model.canApprove)
        #expect(model.error == nil)
        await payment.sockets.waitUntilClosed()
    }

    @Test
    func `Closing the review while sending still delivers the transaction`() async throws {
        let gate = Suspension()
        let payment = try LocalPaymentReview(statuses: [.status(.finalized)], sent: .sending(gate: gate))
        let model = payment.model
        try await payment.model.runReview()
        model.approve()
        let attempt = model.attempt
        let review = Task { await model.run(attempt) }
        await gate.waitUntilStarted()

        review.cancel()
        gate.resume()
        await review.value

        let record = try #require(model.record)
        #expect(model.error == nil)
        #expect(await payment.transactions.outcome(of: record) == .succeeded)
        #expect(model.outcome == .succeeded)
        await payment.sockets.waitUntilClosed()
    }

    @Test
    func `A failed transaction shows its outcome`() async throws {
        let failure = TransactionError(name: "InstructionError",
                                       details: .array([.integer(0), .object(["Custom": .integer(1)])]))
        let payment = try LocalPaymentReview(statuses: [.status(.finalized, error: failure)])
        let model = payment.model
        try await payment.model.runReview()

        model.approve()
        await model.run(model.attempt)

        #expect(await payment.transactions.outcome(of: try #require(model.record)) == .failed)
        #expect(model.outcome == .failed)
        #expect(model.submission != nil)
        await payment.sockets.waitUntilClosed()
    }

    @Test
    func `Trying a dropped transaction again reviews it anew`() async throws {
        let payment = try LocalPaymentReview(statuses: [.status(nil)], height: 600)
        let model = payment.model
        try await payment.model.runReview()
        model.approve()
        await model.run(model.attempt)
        try #require(await payment.transactions.outcome(of: try #require(model.record)) == .dropped)
        try #require(model.outcome == .dropped)
        await payment.sockets.waitUntilClosed()

        model.tryAgain()
        let attempt = try #require(model.attempt)
        await model.run(attempt)

        #expect(attempt.work == .review)
        #expect(model.review == LocalPaymentReview.costs)
        #expect(model.outcome == nil)
        #expect(model.submission == nil)
        #expect(model.canApprove)
        #expect(try await payment.preparation.simulations() == 2)
    }

    @Test
    func `A stopped watch keeps the review waiting until a later watch settles it`() async throws {
        let refusal = Self.rateLimit
        let sockets = SocketSequence { $0 == 0 ? SocketSequence.failing(with: refusal) : SocketSequence.watch() }
        let payment = try LocalPaymentReview(statuses: [.status(.finalized)], sockets: sockets)
        let model = payment.model
        try await payment.model.runReview()
        model.approve()
        await model.run(model.attempt)
        let record = try #require(model.record)
        await #expect(throws: (any Error).self) { try await payment.transactions.watch(record.id, for: record.key) }

        #expect(model.isSending)
        #expect(model.outcome == nil)
        #expect(model.error == nil)

        await payment.transactions.resume()

        #expect(await payment.transactions.outcome(of: record) == .succeeded)
        #expect(model.outcome == .succeeded)
        #expect(!model.isSending)
        #expect(sockets.sockets.count == 2)
        await sockets.waitUntilClosed()
    }

    @Test
    func `A cancelled authentication keeps reviewing with a new simulation`() async throws {
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery, error: CancellationError())
        let payment = try LocalPaymentReview(store: store)
        let model = payment.model
        try await payment.model.runReview()

        model.approve()
        await model.run(model.attempt)

        #expect(model.review == LocalPaymentReview.costs)
        #expect(model.error == nil)
        #expect(model.submission == nil)
        #expect(model.canApprove)
        #expect(await store.reads.count == 1)
        #expect(try await payment.preparation.simulations() == 2)
    }

    @Test
    func `A transaction that can't be signed reviews again on retry`() async throws {
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery, error: CocoaError(.fileReadUnknown))
        let payment = try LocalPaymentReview(store: store)
        let model = payment.model
        try await payment.model.runReview()
        model.approve()
        await model.run(model.attempt)
        try #require(model.error == .notSent)
        #expect(model.submission == nil)
        #expect(!model.canApprove)

        model.retry()
        await model.run(model.attempt)

        #expect(model.canApprove)
        #expect(try await payment.preparation.simulations() == 2)
    }

    @Test
    func `Refreshing a review simulates it again`() async throws {
        let payment = try LocalPaymentReview()
        let model = payment.model
        try await payment.model.runReview()

        await model.refreshReview()

        #expect(model.review == LocalPaymentReview.costs)
        #expect(model.canApprove)
        #expect(try await payment.preparation.simulations() == 2)
    }

    @Test
    func `Refreshing skips a review that's being sent`() async throws {
        let payment = try LocalPaymentReview()
        let model = payment.model
        try await payment.model.runReview()
        model.approve()

        await model.refreshReview()

        #expect(try await payment.preparation.simulations() == 1)
    }
}
