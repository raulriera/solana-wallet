import Foundation
import Testing
import Transactions
@testable import RPC
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TransactionReviewModelTests {
    private static let rateLimit = RPCError.http(statusCode: 429, retryAfter: "3")
    nonisolated private static let slotError = RPCError.server(code: -32016,
                                                               message: "Minimum context slot has not been reached")

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
    func `A preliminary transaction is sent before the proposal's own with one authentication`() async throws {
        let review = try LocalSteppedReview(preliminaryCount: 1, statuses: [.status(.finalized)])
        let model = review.model
        try await model.runReview()

        model.approve()
        await model.run(model.attempt)

        let shared = await review.recovery.shared
        #expect(model.outcome == .succeeded)
        #expect(await review.sent.requests.count == 2)
        #expect(shared.count == 1)
        #expect(await shared.first?.store.reads.count == 2)
        #expect(await review.recovery.reads.isEmpty)
        await review.sockets.waitUntilClosed()
    }

    @Test(arguments: [
        (Self.slotError, 1),
        (RPCError.server(code: -32602, message: "Invalid params"), 2),
    ])
    func `Retrying a review whose simulation failed prepares again only after an error that can't clear`(
        error: RPCError, prepareCount: Int
    ) async throws {
        let review = try LocalSteppedReview(preliminaryCount: 0, failingSimulations: [0: error], statuses: [])
        let model = review.model
        model.prepareReview()
        await model.run(model.attempt)
        try #require(model.error == .preparationFailed)

        model.retry()
        await model.run(model.attempt)

        #expect(model.canApprove)
        #expect(model.proposal.simulations.count == 2)
        #expect(model.proposal.simulations.prepareCount == prepareCount)
    }

    @Test(arguments: [
        ([1: Self.slotError], [Duration.seconds(2)]),
        ([1: Self.slotError, 2: Self.slotError], [Duration.seconds(2), .seconds(4)]),
    ])
    func `An error that can clear retries the next simulation after doubling waits without another preparation`(
        failingSimulations: [Int: RPCError], expectedWaits: [Duration]
    ) async throws {
        let review = try LocalSteppedReview(preliminaryCount: 1, failingSimulations: failingSimulations,
                                            statuses: [.status(.finalized)])
        let model = review.model
        try await model.runReview()
        var waits = review.clock.waits.makeAsyncIterator()

        model.approve()
        let send = Task { await model.run(model.attempt) }
        let advanced = try await review.clock.advanceWaits(&waits, count: expectedWaits.count)
        await send.value

        #expect(advanced == expectedWaits)
        #expect(model.outcome == .succeeded)
        #expect(model.proposal.simulations.count == 2 + failingSimulations.count)
        #expect(model.proposal.simulations.prepareCount == 2)
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `Retrying a send whose next simulation kept failing with an error that can clear keeps its preparation`()
        async throws {
        let review = try LocalSteppedReview(
            preliminaryCount: 1, failingSimulations: [1: Self.slotError, 2: Self.slotError, 3: Self.slotError],
            statuses: [.status(.finalized)]
        )
        let model = review.model
        try await model.runReview()
        var waits = review.clock.waits.makeAsyncIterator()
        model.approve()
        let send = Task { await model.run(model.attempt) }
        try await review.clock.advanceWaits(&waits, count: 2)
        await send.value
        try #require(model.error == .notSent)

        model.retry()
        await model.run(model.attempt)

        #expect(model.canApprove)
        #expect(model.proposal.simulations.count == 5)
        #expect(model.proposal.simulations.prepareCount == 2)
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `Cancelling a send while it waits to retry its next transaction ends it without another simulation`()
        async throws {
        let review = try LocalSteppedReview(preliminaryCount: 1, failingSimulations: [1: Self.slotError],
                                            statuses: [.status(.finalized)])
        let model = review.model
        try await model.runReview()
        var waits = review.clock.waits.makeAsyncIterator()
        model.approve()
        let send = Task { await model.run(model.attempt) }
        _ = try await review.clock.durationToNextWait(&waits)

        send.cancel()
        await send.value

        #expect(model.record == nil)
        #expect(model.attempt == nil)
        #expect(model.proposal.simulations.count == 2)
        #expect(await review.sent.requests.count == 1)
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `A preliminary transaction that keeps dropping is sent three times with one preparation`() async throws {
        let review = try LocalSteppedReview(preliminaryCount: .max, statuses: [.status(nil)], height: 600)
        let model = review.model
        try await model.runReview()

        model.approve()
        await model.run(model.attempt)

        #expect(model.record == nil)
        #expect(model.error == .notSent)
        #expect(model.proposal.simulations.prepareCount == 1)
        #expect(await review.sent.requests.count == 3)
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `A send ends before a transaction that needs more transactions than the person approved`() async throws {
        let review = try LocalSteppedReview(preliminaryCount: 2, reportedFollowing: 1, statuses: [.status(.finalized)])
        let model = review.model
        try await model.runReview()

        model.approve()
        await model.run(model.attempt)

        #expect(model.record == nil)
        #expect(model.error == .notSent)
        #expect(await review.sent.requests.count == 1)
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `A dropped transaction whose preparation the proposal rejects is prepared again`() async throws {
        let review = try LocalSteppedReview(preliminaryCount: .max,
                                            failingSimulations: [1: SendError.preparationFailed],
                                            statuses: [.status(nil)], height: 600)
        let model = review.model
        try await model.runReview()

        model.approve()
        await model.run(model.attempt)

        #expect(model.error == .notSent)
        #expect(model.proposal.simulations.prepareCount == 2)
        #expect(model.proposal.simulations.count == 4)
        #expect(await review.sent.requests.count == 3)
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `Trying again after a send ends beyond the approved transactions keeps the next preparation`() async throws {
        let review = try LocalSteppedReview(preliminaryCount: 2, reportedFollowing: 1, statuses: [.status(.finalized)])
        let model = review.model
        try await model.runReview()
        model.approve()
        await model.run(model.attempt)
        try #require(model.error == .notSent)

        model.retry()
        await model.run(model.attempt)

        #expect(model.canApprove)
        #expect(model.proposal.simulations.count == 3)
        #expect(model.proposal.simulations.prepareCount == 2)
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `Stopping a send ends it before its next transaction`() async throws {
        let review = try LocalSteppedReview(preliminaryCount: 1, statuses: [.status(.finalized)])
        let model = review.model
        try await model.runReview()

        model.approve()
        model.stopSending()
        await model.run(model.attempt)

        #expect(model.record == nil)
        #expect(model.error == .notSent)
        #expect(await review.sent.requests.count == 1)
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `Stopping a send while it prepares its next transaction ends it before that transaction`() async throws {
        let review = try LocalSteppedReview(preliminaryCount: 1, statuses: [.status(.finalized)])
        let model = review.model
        try await model.runReview()
        model.proposal.simulations.onPrepare = { [weak model] in model?.stopSending() }

        model.approve()
        await model.run(model.attempt)

        #expect(model.record == nil)
        #expect(model.error == .notSent)
        #expect(model.proposal.simulations.prepareCount == 2)
        #expect(await review.sent.requests.count == 1)
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `Trying again after a send stops while preparing keeps the next preparation`() async throws {
        let review = try LocalSteppedReview(preliminaryCount: 1, statuses: [.status(.finalized)])
        let model = review.model
        try await model.runReview()
        model.proposal.simulations.onPrepare = { [weak model] in model?.stopSending() }
        model.approve()
        await model.run(model.attempt)
        try #require(model.error == .notSent)

        model.retry()
        await model.run(model.attempt)

        #expect(model.canApprove)
        #expect(model.proposal.simulations.count == 3)
        #expect(model.proposal.simulations.prepareCount == 2)
        await review.sockets.waitUntilClosed()
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

    @Test(arguments: [
        ([Int: SendError](), 1, 2),
        ([1: .preparationFailed], 2, 3),
    ])
    func `Trying a dropped transaction again reviews it anew, preparing only a preparation the proposal rejects`(
        failingSimulations: [Int: SendError], prepareCount: Int, simulationCount: Int
    ) async throws {
        let review = try LocalSteppedReview(preliminaryCount: 0, failingSimulations: failingSimulations,
                                            statuses: [.status(nil)], height: 600)
        let model = review.model
        try await model.runReview()
        model.approve()
        await model.run(model.attempt)
        try #require(await review.transactions.outcome(of: try #require(model.record)) == .dropped)
        try #require(model.outcome == .dropped)
        await review.sockets.waitUntilClosed()

        model.tryAgain()
        let attempt = try #require(model.attempt)
        await model.run(attempt)

        #expect(attempt.work == .review)
        #expect(model.review == LocalPaymentReview.costs)
        #expect(model.outcome == nil)
        #expect(model.submission == nil)
        #expect(model.canApprove)
        #expect(model.error == nil)
        #expect(model.proposal.simulations.count == simulationCount)
        #expect(model.proposal.simulations.prepareCount == prepareCount)
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
