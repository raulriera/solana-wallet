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
    nonisolated private static let invalidParams = RPCError.server(code: -32602, message: "Invalid params")

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

        model.prepareReview()

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
        #expect(record.network == .devnet)

        #expect(try await payment.transactions.settledOutcome(of: record).status == .succeeded(slot: 405))
        #expect(model.outcome?.status == .succeeded(slot: 405))
        #expect(!model.isSending)
        #expect(model.isSent)
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
        #expect(try await payment.transactions.settledOutcome(of: record).status == .succeeded(slot: 405))
        #expect(model.outcome?.status == .succeeded(slot: 405))
        await payment.sockets.waitUntilClosed()
    }

    @Test
    func `A preliminary transaction is sent before the proposal's own with one authentication`() async throws {
        let review = try LocalSteppedReview(followingTransactions: [1, 0], statuses: [.status(.finalized)])
        let model = review.model
        try await model.runReview()

        model.approve()
        await model.run(model.attempt)

        let shared = await review.recovery.shared
        #expect(model.outcome?.status == .succeeded(slot: 405))
        #expect(await review.sent.requests.count == 2)
        #expect(shared.count == 1)
        #expect(await shared.first?.store.reads.count == 2)
        #expect(await review.recovery.reads.isEmpty)
        await review.sockets.waitUntilClosed()
    }

    @Test(arguments: [
        (Self.slotError, 1),
        (Self.invalidParams, 2),
    ])
    func `Retrying a review whose simulation failed prepares again only after an error that can't clear`(
        error: RPCError, prepareCount: Int
    ) async throws {
        let review = try LocalSteppedReview(followingTransactions: [0], failingSimulations: [0: error], statuses: [])
        let model = review.model
        model.prepareReview()
        await model.run(model.attempt)
        try #require(model.error == .preparationFailed)

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.canApprove)
        #expect(model.proposal.simulations.prepareCount == prepareCount)
    }

    @Test
    func `Retrying with a kept preparation that the proposal rejects for another reason doesn't prepare again`()
        async throws {
        let review = try LocalSteppedReview(
            followingTransactions: [0],
            failingSimulations: [0: Self.slotError, 1: SendError.notEnoughSOL, 2: SendError.notEnoughSOL],
            statuses: []
        )
        let model = review.model
        model.prepareReview()
        await model.run(model.attempt)
        try #require(model.error == .preparationFailed)

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.error == .notEnoughSOL)
        #expect(model.proposal.simulations.prepareCount == 1)
    }

    @Test(arguments: [
        ([1: Self.slotError], [Duration.seconds(2)], 3),
        ([1: Self.slotError, 2: Self.slotError], [Duration.seconds(2), .seconds(4)], 4),
    ])
    func `An error that can clear retries the next simulation after doubling waits without another preparation`(
        failingSimulations: [Int: RPCError], expectedWaits: [Duration], simulationCount: Int
    ) async throws {
        let review = try LocalSteppedReview(followingTransactions: [1, 0], failingSimulations: failingSimulations,
                                            statuses: [.status(.finalized)])
        let model = review.model
        try await model.runReview()
        var waits = review.clock.waits.makeAsyncIterator()

        model.approve()
        let send = Task { await model.run(model.attempt) }
        let advanced = try await review.clock.advanceWaits(&waits, count: expectedWaits.count)
        await send.value

        #expect(advanced == expectedWaits)
        #expect(model.outcome?.status == .succeeded(slot: 405))
        #expect(model.proposal.simulations.count == simulationCount)
        #expect(model.proposal.simulations.prepareCount == 2)
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `Retrying a send whose next simulation kept failing with an error that can clear keeps its preparation`()
        async throws {
        let review = try LocalSteppedReview(
            followingTransactions: [1, 0],
            failingSimulations: [1: Self.slotError, 2: Self.slotError, 3: Self.slotError],
            statuses: [.status(.finalized)]
        )
        let model = review.model
        try await model.runReview()
        var waits = review.clock.waits.makeAsyncIterator()
        model.approve()
        let send = Task { await model.run(model.attempt) }
        try await review.clock.advanceWaits(&waits, count: 2)
        await send.value
        try #require(model.error == .notFinished)

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.canApprove)
        #expect(model.proposal.simulations.prepareCount == 2)
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `Cancelling a send while it waits to retry its next transaction ends it without another simulation`()
        async throws {
        let review = try LocalSteppedReview(followingTransactions: [1, 0], failingSimulations: [1: Self.slotError],
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

    @Test(arguments: [
        ([Int: SendError](), SendError.notSent, 3),
        ([1: .preparationFailed], .preparationFailed, 1),
    ])
    func `A dropped preliminary transaction is sent again only with its preparation`(
        failingSimulations: [Int: SendError], error: SendError, sendCount: Int
    ) async throws {
        let review = try LocalSteppedReview(followingTransactions: [1], failingSimulations: failingSimulations,
                                            statuses: [.status(nil)], height: 600)
        let model = review.model
        try await model.runReview()

        model.approve()
        await model.run(model.attempt)

        #expect(model.record == nil)
        #expect(model.error == error)
        #expect(model.proposal.simulations.prepareCount == 1)
        #expect(await review.sent.requests.count == sendCount)
        await review.sockets.waitUntilClosed()
    }

    @Test(arguments: [
        ([1, 0], GetSignatureStatuses.Response.status(.finalized, error: .instructionError(0, custom: 1)),
         UInt64(500), false, SendError.notFinished, 1),
        ([1, 0], .status(.finalized), 500, true, .notFinished, 1),
        ([1, 1, 0], .status(.finalized), 500, false, .notFinished, 1),
        ([1], .status(nil), 600, false, .notSent, 3),
    ])
    func `A send that ends after one of its transactions landed isn't finished, and before that isn't sent`(
        followingTransactions: [Int], status: GetSignatureStatuses.Response, height: UInt64, isStopped: Bool,
        error: SendError, sendCount: Int
    ) async throws {
        let review = try LocalSteppedReview(followingTransactions: followingTransactions, statuses: [status],
                                            height: height)
        let model = review.model
        try await model.runReview()

        model.approve()
        if isStopped { model.stopSending() }
        await model.run(model.attempt)

        #expect(model.record == nil)
        #expect(model.error == error)
        #expect(await review.sent.requests.count == sendCount)
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `A preliminary transaction whose watch stops keeps the send waiting until a later watch settles it`()
        async throws {
        let refusal = Self.rateLimit
        let sockets = SocketSequence { $0 == 0 ? SocketSequence.failing(with: refusal) : SocketSequence.watch() }
        let review = try LocalSteppedReview(followingTransactions: [1, 0], statuses: [.status(.finalized)],
                                            sockets: sockets)
        let model = review.model
        try await model.runReview()
        model.approve()
        let send = Task { await model.run(model.attempt) }
        while sockets.sockets.count < 2 {
            await review.transactions.resume()
            await Task.yield()
        }

        #expect(model.isSending)
        #expect(!model.canApprove)
        #expect(model.error == nil)

        await send.value

        #expect(model.outcome?.status == .succeeded(slot: 405))
        #expect(await review.sent.requests.count == 2)
        #expect(sockets.sockets.count == 3)
        await sockets.waitUntilClosed()
    }

    @Test
    func `Two preliminary transactions that succeed are followed by the proposal's own`() async throws {
        let review = try LocalSteppedReview(followingTransactions: [2, 1, 0], statuses: [.status(.finalized)])
        let model = review.model
        try await model.runReview()

        model.approve()
        await model.run(model.attempt)

        #expect(model.outcome?.status == .succeeded(slot: 405))
        #expect(await review.sent.requests.count == 3)
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `A sent proposal's review is the review of its own transaction, not of a preliminary one`() async throws {
        let review = try LocalSteppedReview(followingTransactions: [1, 0], statuses: [.status(.finalized)])
        let model = review.model
        try await model.runReview()
        let approved = try #require(model.review)

        model.approve()
        await model.run(model.attempt)

        #expect(model.outcome?.status == .succeeded(slot: 405))
        #expect(try #require(model.review).networkFee * 2 == approved.networkFee)
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `The proposal's own transaction that drops after a preliminary one is sent again`() async throws {
        let review = try LocalSteppedReview(followingTransactions: [1, 0],
                                            statuses: [.status(.finalized), .status(nil), .status(.finalized)],
                                            height: 600)
        let model = review.model
        try await model.runReview()

        model.approve()
        await model.run(model.attempt)

        #expect(model.outcome?.status == .succeeded(slot: 405))
        #expect(await review.sent.requests.count == 3)
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `Cancelling a send while a preliminary transaction waits for its outcome ends it with nothing to approve`()
        async throws {
        let review = try LocalSteppedReview(followingTransactions: [1, 0], statuses: [.status(nil)])
        let model = review.model
        try await model.runReview()
        var openings = review.sockets.openings.makeAsyncIterator()
        model.approve()
        let send = Task { await model.run(model.attempt) }
        _ = await openings.next()

        send.cancel()
        await send.value

        #expect(model.error == nil)
        #expect(!model.canApprove)
        try await review.transactions.erase()
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `A send whose next transaction the proposal rejects shows the proposal's error`() async throws {
        let review = try LocalSteppedReview(followingTransactions: [1, 0],
                                            failingSimulations: [1: SendError.notEnoughSOL],
                                            statuses: [.status(.finalized)])
        let model = review.model
        try await model.runReview()

        model.approve()
        await model.run(model.attempt)

        #expect(model.record == nil)
        #expect(model.error == .notEnoughSOL)
        #expect(await review.sent.requests.count == 1)
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `Trying again after a send ends beyond the approved transactions keeps the next preparation`() async throws {
        let review = try LocalSteppedReview(followingTransactions: [1, 1, 0], statuses: [.status(.finalized)])
        let model = review.model
        try await model.runReview()
        model.approve()
        await model.run(model.attempt)
        try #require(model.error == .notFinished)

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.canApprove)
        #expect(model.proposal.simulations.prepareCount == 2)
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `Stopping a send while it prepares its next transaction ends it before that transaction`() async throws {
        let review = try LocalSteppedReview(followingTransactions: [1, 0], statuses: [.status(.finalized)])
        let model = review.model
        try await model.runReview()
        model.proposal.simulations.onPrepare = { [weak model] in model?.stopSending() }

        model.approve()
        await model.run(model.attempt)

        #expect(model.record == nil)
        #expect(model.error == .notFinished)
        #expect(model.proposal.simulations.prepareCount == 2)
        #expect(await review.sent.requests.count == 1)
        await review.sockets.waitUntilClosed()
    }

    @Test
    func `A failed transaction shows its outcome`() async throws {
        let payment = try LocalPaymentReview(statuses: [.status(.finalized, error: .instructionError(0, custom: 1))])
        let model = payment.model
        try await payment.model.runReview()

        model.approve()
        await model.run(model.attempt)

        let failed = TransactionOutcome.Status.failed(slot: 405, .insufficientFunds(payment.account.address))

        #expect(try await payment.transactions.settledOutcome(of: try #require(model.record)).status == failed)
        #expect(model.outcome?.status == failed)
        await payment.sockets.waitUntilClosed()
    }

    @Test(arguments: [
        ([Int: SendError](), 1, 2),
        ([1: .preparationFailed], 2, 3),
    ])
    func `Trying a dropped transaction again reviews it anew, preparing only a preparation the proposal rejects`(
        failingSimulations: [Int: SendError], prepareCount: Int, simulationCount: Int
    ) async throws {
        let review = try LocalSteppedReview(followingTransactions: [0], failingSimulations: failingSimulations,
                                            statuses: [.status(nil)], height: 600)
        let model = review.model
        try await model.runReview()
        model.approve()
        await model.run(model.attempt)
        try #require(try await review.transactions.settledOutcome(of: try #require(model.record)).status == .dropped)
        try #require(model.outcome?.status == .dropped)
        await review.sockets.waitUntilClosed()

        model.tryAgain()
        let attempt = try #require(model.attempt)
        await model.run(attempt)

        #expect(attempt.work == .review)
        #expect(model.review == LocalPaymentReview.costs)
        #expect(model.outcome == nil)
        #expect(model.canApprove)
        #expect(model.error == nil)
        #expect(model.proposal.simulations.count == simulationCount)
        #expect(model.proposal.simulations.prepareCount == prepareCount)
    }

    @Test
    func `A stopped watch keeps the outcome pending until a later watch settles it`() async throws {
        let refusal = Self.rateLimit
        let sockets = SocketSequence { $0 == 0 ? SocketSequence.failing(with: refusal) : SocketSequence.watch() }
        let payment = try LocalPaymentReview(statuses: [.status(.finalized)], sockets: sockets)
        let model = payment.model
        try await payment.model.runReview()
        model.approve()
        await model.run(model.attempt)
        let record = try #require(model.record)
        await #expect(throws: (any Error).self) { try await payment.transactions.watch(record.id, for: record.key) }

        #expect(model.outcome?.status == .pending)
        #expect(model.isSending)
        #expect(model.error == nil)

        await payment.transactions.resume()

        #expect(try await payment.transactions.settledOutcome(of: record).status == .succeeded(slot: 405))
        #expect(model.outcome?.status == .succeeded(slot: 405))
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
        #expect(model.outcome == nil)
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
        #expect(model.outcome == nil)
        #expect(!model.canApprove)

        model.prepareReview()
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
    func `A refresh error keeps later refreshes simulating the review`() async throws {
        let review = try LocalSteppedReview(followingTransactions: [0], failingSimulations: [1: Self.invalidParams],
                                            statuses: [])
        let model = review.model
        try await model.runReview()
        await model.refreshReview()
        try #require(model.error == .preparationFailed)

        await model.refreshReview()

        #expect(model.canApprove)
        #expect(model.proposal.simulations.count == 3)
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
