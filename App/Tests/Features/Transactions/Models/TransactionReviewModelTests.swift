import Foundation
@testable import RPC
import Testing
import Transactions
@testable import widgets

/// Verifies a transaction's review, approval, and settling through a payment's review over the real transaction
/// coordinator, with local responses and sockets.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TransactionReviewModelTests {
    /// A provider's rate limit.
    private static let rateLimit = RPCError.http(statusCode: 429, retryAfter: "3")

    /// Reviewing simulates the transaction and shows its review, which can then be approved.
    /// - Throws: A fixture error.
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

    /// A simulation that the proposal rejects shows the proposal's own error without a review.
    /// - Throws: A fixture error.
    @Test
    func `A failed simulation shows the proposal's error without a review`() async throws {
        let error = TransactionError(name: "InsufficientFundsForFee", details: nil)
        let model = try LocalPaymentReview(simulation: LocalPaymentReview.execution(error: error)).model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.error == .notEnoughSOL)
        #expect(model.review == nil)
        #expect(!model.canApprove)
    }

    /// An error that isn't the proposal's own, such as a provider's rate limit, is a preparation failure, which
    /// retrying reviews again.
    /// - Throws: A fixture error.
    @Test
    func `Another error is a preparation failure that retrying reviews again`() async throws {
        let payment = try LocalPaymentReview()
        let limited = HTTPResponses([:], error: Self.rateLimit)
        let transactions = TransactionStore.inMemory { network in
            try TransactionCoordinator(rpc: Solana(network: network, transport: limited),
                                       store: UnavailableRecoveryStore(), rpcs: nil)
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

    /// Approving signs and sends the reviewed transaction, after which its record shows how it settled.
    /// - Throws: A fixture error.
    @Test
    func `A landed transaction shows its outcome from its record`() async throws {
        let payment = try LocalPaymentReview(statuses: [.status(.finalized)])
        let model = payment.model
        try await payment.review()

        model.approve()
        await model.run(model.attempt)
        let record = try #require(model.record)
        #expect(record.kind == .payment(recipient: model.proposal.recipient.address, mint: nil,
                                        units: 1_000_000_000))
        #expect(model.submission?.network == .devnet)

        #expect(await payment.transactions.settledStatus(of: record) == .succeeded)
        #expect(model.outcome == .succeeded)
        #expect(!model.isSending)
        #expect(!model.canApprove)
        #expect(model.error == nil)
        await payment.sockets.waitUntilClosed()
    }

    /// Closing the review while the transaction is sent stops only the review's wait: the transaction is still
    /// delivered, recorded, and watched until it settles.
    /// - Throws: A fixture error.
    @Test
    func `Closing the review while sending still delivers the transaction`() async throws {
        let gate = Suspension()
        let payment = try LocalPaymentReview(statuses: [.status(.finalized)], sent: .sending(gate: gate))
        let model = payment.model
        try await payment.review()
        model.approve()
        let attempt = model.attempt
        let review = Task { await model.run(attempt) }
        await gate.waitUntilStarted()

        // Closing the sheet cancels its task.
        review.cancel()
        gate.resume()
        await review.value

        let record = try #require(await payment.records.value?.first)
        #expect(model.record?.id == record.id)
        #expect(model.error == nil)
        #expect(await payment.transactions.settledStatus(of: record) == .succeeded)
        #expect(model.outcome == .succeeded)
        await payment.sockets.waitUntilClosed()
    }

    /// A transaction that lands and fails shows its outcome and keeps its signature.
    /// - Throws: A fixture error.
    @Test
    func `A failed transaction shows its outcome`() async throws {
        let failure = TransactionError(name: "InstructionError",
                                       details: .array([.integer(0), .object(["Custom": .integer(1)])]))
        let payment = try LocalPaymentReview(statuses: [.status(.finalized, error: failure)])
        let model = payment.model
        try await payment.review()

        model.approve()
        await model.run(model.attempt)

        #expect(await payment.transactions.settledStatus(of: try #require(model.record)) == .failed)
        #expect(model.outcome == .failed)
        #expect(model.submission != nil)
        await payment.sockets.waitUntilClosed()
    }

    /// A dropped transaction keeps its signature and can be tried again, which reviews the same proposal anew.
    /// - Throws: A fixture error.
    @Test
    func `Trying a dropped transaction again reviews it anew`() async throws {
        // The epoch's block height is past the blockhash's last valid block height, 550, and no status exists.
        let payment = try LocalPaymentReview(statuses: [.status(nil)], height: 600)
        let model = payment.model
        try await payment.review()
        model.approve()
        await model.run(model.attempt)
        try #require(await payment.transactions.settledStatus(of: try #require(model.record)) == .dropped)
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
        #expect(try await payment.simulations() == 2)
    }

    /// A watch that a rate limit stops leaves the review waiting without an error, and a later watch of the same
    /// record shows the result.
    /// - Throws: A fixture error.
    @Test
    func `A stopped watch keeps the review waiting until a later watch settles it`() async throws {
        let refusal = Self.rateLimit
        let sockets = SocketSequence { $0 == 0 ? SocketSequence.failing(with: refusal) : SocketSequence.watch() }
        let payment = try LocalPaymentReview(statuses: [.status(.finalized)], sockets: sockets)
        let model = payment.model
        try await payment.review()
        model.approve()
        await model.run(model.attempt)
        let record = try #require(model.record)
        // The first watch ends with the rate limit, which only a caller of the watch reads.
        await #expect(throws: (any Error).self) { try await payment.transactions.watch(record.id, for: record.key) }

        #expect(model.status == .pending)
        #expect(model.isSending)
        #expect(model.outcome == nil)
        #expect(model.error == nil)

        await payment.transactions.resume()

        #expect(await payment.transactions.settledStatus(of: record) == .succeeded)
        #expect(model.outcome == .succeeded)
        #expect(!model.isSending)
        #expect(sockets.sockets.count == 2)
        await sockets.waitUntilClosed()
    }

    /// A cancelled authentication uses up the simulation, so the model simulates the same preparation again and keeps
    /// reviewing, without an error or a submission.
    /// - Throws: A fixture error.
    @Test
    func `A cancelled authentication keeps reviewing with a new simulation`() async throws {
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery, error: CancellationError())
        let payment = try LocalPaymentReview(store: store)
        let model = payment.model
        try await payment.review()

        model.approve()
        await model.run(model.attempt)

        #expect(model.review == LocalPaymentReview.costs)
        #expect(model.error == nil)
        #expect(model.submission == nil)
        #expect(model.canApprove)
        #expect(await store.reads.count == 1)
        #expect(try await payment.simulations() == 2)
    }

    /// A transaction that can't be signed sends nothing and uses up its simulation, so retrying reviews it again.
    /// - Throws: A fixture error.
    @Test
    func `A transaction that can't be signed reviews again on retry`() async throws {
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery, error: CocoaError(.fileReadUnknown))
        let payment = try LocalPaymentReview(store: store)
        let model = payment.model
        try await payment.review()
        model.approve()
        await model.run(model.attempt)
        try #require(model.error == .notSent)
        #expect(model.submission == nil)
        #expect(!model.canApprove)

        model.retry()
        await model.run(model.attempt)

        #expect(model.canApprove)
        #expect(try await payment.simulations() == 2)
    }

    /// Refreshing an open review simulates the same transaction again and keeps the same review.
    /// - Throws: A fixture error.
    @Test
    func `Refreshing a review simulates it again`() async throws {
        let payment = try LocalPaymentReview()
        let model = payment.model
        try await payment.review()

        await model.refreshReview()

        #expect(model.review == LocalPaymentReview.costs)
        #expect(model.canApprove)
        #expect(try await payment.simulations() == 2)
    }

    /// A review that's being sent isn't simulated again, so the approved transaction stays the one that's signed.
    /// - Throws: A fixture error.
    @Test
    func `Refreshing skips a review that's being sent`() async throws {
        let payment = try LocalPaymentReview()
        let model = payment.model
        try await payment.review()
        model.approve()

        await model.refreshReview()

        #expect(try await payment.simulations() == 1)
    }
}
