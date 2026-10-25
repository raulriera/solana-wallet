import Foundation
@testable import RPC
import Testing
import Transactions
@testable import widgets

/// Verifies payments from the keypad: their reviews, sending, and watch through the real transaction coordinator, with
/// local responses and sockets.
///
/// Each payment sends 1 SOL from the fixture account's 2 SOL to a recipient named Bruno. Every simulation reports a
/// 10,000-lamport network fee.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SendModelTests {
    /// The network fee of every simulation, in lamports.
    private static let networkFee: UInt64 = 10_000
    /// The review of every successful simulation of a SOL payment.
    private static let review = SendModel.Review(networkFee: networkFee, accountDeposit: nil)
    /// A provider's rate limit.
    private static let rateLimit = RPCError.http(statusCode: 429, retryAfter: "3")
    /// The account's SOL, without a price, so the keypad types SOL.
    private static let sol = PaymentToken(mint: nil, symbol: "SOL", balance: 2, price: nil, decimals: 9)

    /// The local responses and connections behind a payment.
    private struct Payment {
        /// The model under test.
        let model: SendModel
        /// The keypad's payment, with 1 SOL typed.
        let keypad: PaymentModel
        /// The window's portfolio, which counts refreshes.
        let portfolio: RecordingPortfolio
        /// The responses that answer the coordinator's preparation reads and simulations.
        let preparation: HTTPResponses
        /// The connections of the coordinator's watch.
        let sockets: SocketSequence
    }

    /// Reviewing simulates the payment and shows its network fee, without an account deposit for SOL.
    /// - Throws: A fixture error.
    @Test
    func `Reviewing shows the network fee`() async throws {
        let model = try Self.payment().model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.review == Self.review)
        #expect(model.canApprove)
        #expect(model.error == nil)
        #expect(model.attempt == nil)
    }

    /// A simulation that runs out of SOL can't be sent and can't be tried again; another execution failure is a
    /// preparation failure; neither shows a review.
    /// - Parameters:
    ///   - error: The simulated execution error.
    ///   - expected: The model's error.
    /// - Throws: A fixture error.
    @Test(arguments: [
        (TransactionError(name: "InsufficientFundsForFee", details: nil), SendError.notEnoughSOL),
        (TransactionError(name: "InstructionError", details: .array([.integer(0), .object(["Custom": .integer(6001)])])),
         .preparationFailed),
    ])
    func `A failed simulation shows its error without a review`(error: TransactionError,
                                                                expected: SendError) async throws {
        let model = try Self.payment(simulation: Self.execution(error: error)).model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.error == expected)
        #expect(model.review == nil)
        #expect(!model.canApprove)
    }

    /// Approving signs and sends the reviewed payment and watches it until it lands, which clears the keypad's amount
    /// and reads the balances again.
    /// - Throws: A fixture error.
    @Test
    func `A landed payment clears the amount and reads the balances again`() async throws {
        let payment = try Self.payment(statuses: [Self.status(.finalized)])
        let model = payment.model
        try await Self.review(model)

        model.approve()
        await model.run(model.attempt)

        #expect(model.outcome == .succeeded)
        #expect(try #require(model.submission).network == .devnet)
        #expect(payment.keypad.quantity == 0)
        #expect(payment.portfolio.refreshes == 1)
        #expect(model.amount.quantity == 1)
        #expect(model.error == nil)
        await payment.sockets.waitUntilClosed()
    }

    /// A payment that lands and fails paid its network fee, so the balances are read again, but the amount stays
    /// typed.
    /// - Throws: A fixture error.
    @Test
    func `A failed payment keeps the amount and reads the balances again`() async throws {
        let failure = TransactionError(name: "InstructionError",
                                       details: .array([.integer(0), .object(["Custom": .integer(1)])]))
        let payment = try Self.payment(statuses: [Self.status(.finalized, error: failure)])
        let model = payment.model
        try await Self.review(model)

        model.approve()
        await model.run(model.attempt)

        #expect(model.outcome == .failed)
        #expect(model.submission != nil)
        #expect(payment.keypad.quantity == 1)
        #expect(payment.portfolio.refreshes == 1)
        await payment.sockets.waitUntilClosed()
    }

    /// A dropped payment keeps its signature, reads no balances, and can be tried again, which reviews the same
    /// amount anew.
    /// - Throws: A fixture error.
    @Test
    func `Trying a dropped payment again reviews the same amount`() async throws {
        // The epoch's block height is past the blockhash's last valid block height, 550, and no status exists.
        let payment = try Self.payment(statuses: [Self.status(nil)], height: 600)
        let model = payment.model
        try await Self.review(model)
        model.approve()
        await model.run(model.attempt)
        try #require(model.outcome == .dropped)
        #expect(model.submission != nil)
        #expect(payment.portfolio.refreshes == 0)
        await payment.sockets.waitUntilClosed()

        model.tryAgain()
        let attempt = try #require(model.attempt)
        await model.run(attempt)

        #expect(attempt.work == .review)
        #expect(model.review == Self.review)
        #expect(model.outcome == nil)
        #expect(model.submission == nil)
        #expect(model.canApprove)
        #expect(try await Self.simulations(of: payment.preparation) == 2)
    }

    /// A watch that a rate limit stops keeps the payment's signature without an outcome, and retrying watches the
    /// same payment again until it settles.
    /// - Throws: A fixture error.
    @Test
    func `Retrying a stopped watch checks the same payment again`() async throws {
        let refusal = Self.rateLimit
        let sockets = SocketSequence { $0 == 0 ? SocketSequence.failing(with: refusal) : SocketSequence.watch() }
        let payment = try Self.payment(statuses: [Self.status(.finalized)], sockets: sockets)
        let model = payment.model
        try await Self.review(model)
        model.approve()
        await model.run(model.attempt)
        try #require(model.error == .watchStopped)
        let submission = try #require(model.submission)
        #expect(model.outcome == nil)

        model.retry()
        let attempt = try #require(model.attempt)
        await model.run(attempt)

        #expect(attempt.work == .check)
        #expect(model.outcome == .succeeded)
        #expect(model.submission == submission)
        #expect(sockets.sockets.count == 2)
        await sockets.waitUntilClosed()
    }

    /// A cancelled authentication uses up the review, so the model simulates the same payment again and keeps
    /// reviewing, without an error or a submission.
    /// - Throws: A fixture error.
    @Test
    func `A cancelled authentication keeps reviewing with a new review`() async throws {
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery, error: CancellationError())
        let payment = try Self.payment(store: store)
        let model = payment.model
        try await Self.review(model)

        model.approve()
        await model.run(model.attempt)

        #expect(model.review == Self.review)
        #expect(model.error == nil)
        #expect(model.submission == nil)
        #expect(model.canApprove)
        #expect(await store.reads.count == 1)
        #expect(try await Self.simulations(of: payment.preparation) == 2)
    }

    /// A payment that can't be signed sends nothing and uses up its review, so retrying simulates it again.
    /// - Throws: A fixture error.
    @Test
    func `A payment that can't be signed reviews again on retry`() async throws {
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery, error: CocoaError(.fileReadUnknown))
        let payment = try Self.payment(store: store)
        let model = payment.model
        try await Self.review(model)
        model.approve()
        await model.run(model.attempt)
        try #require(model.error == .notSent)
        #expect(model.submission == nil)
        #expect(!model.canApprove)

        model.retry()
        await model.run(model.attempt)

        #expect(model.canApprove)
        #expect(try await Self.simulations(of: payment.preparation) == 2)
    }

    /// Refreshing an open review simulates the same payment again and keeps the same review.
    /// - Throws: A fixture error.
    @Test
    func `Refreshing a review simulates it again`() async throws {
        let payment = try Self.payment()
        let model = payment.model
        try await Self.review(model)

        await model.refreshReview()

        #expect(model.review == Self.review)
        #expect(model.canApprove)
        #expect(try await Self.simulations(of: payment.preparation) == 2)
    }

    /// A review that's being sent isn't simulated again, so the approved transaction stays the one that's signed.
    /// - Throws: A fixture error.
    @Test
    func `Refreshing skips a review that's being sent`() async throws {
        let payment = try Self.payment()
        let model = payment.model
        try await Self.review(model)
        model.approve()

        await model.refreshReview()

        #expect(try await Self.simulations(of: payment.preparation) == 1)
    }

    /// The review keeps the amount typed when the person tapped Send, even when the keypad's amount changes.
    /// - Throws: A fixture error.
    @Test
    func `The review keeps the amount typed at Send`() async throws {
        let payment = try Self.payment()

        payment.keypad.press(.digit(5))

        #expect(payment.model.amount.quantity == 1)
        #expect(payment.keypad.quantity == 15)
    }

    /// Creates a payment of 1 SOL from the fixture account on devnet, over a transaction coordinator that answers from
    /// local responses and sockets.
    /// - Parameters:
    ///   - simulation: The simulated execution of every payment.
    ///   - store: The recovery storage that signing reads, or `nil` for the fixture recovery.
    ///   - statuses: The watch's status reads, in arrival order.
    ///   - height: The finalized block height of the watch's epoch reads.
    ///   - sockets: The watch's connections.
    /// - Returns: The model and the local responses and connections behind it.
    /// - Throws: A fixture error.
    private static func payment(simulation: SimulateTransaction.Value = success, store: SigningRecoveryStore? = nil,
                                statuses: [GetSignatureStatuses.Response] = [], height: UInt64 = 500,
                                sockets: SocketSequence = SocketSequence()) throws -> Payment {
        var fixture = try SigningFixture()
        fixture.simulation = SimulateTransaction.Response(context: Context(slot: 402), value: simulation)
        let preparation = try HTTPResponses.preparation(fixture: fixture.preparation)
        let confirmation = try HTTPResponses.confirmation(
            statuses: statuses, epochs: [GetEpochInfo.Response(epoch: 1, absoluteSlot: 1_000, blockHeight: height)]
        )
        let signing = try HTTPResponses.signing()
        let transactions = TransactionCoordinator(
            rpc: preparation.client, configuration: fixture.configuration, preparer: Preparer(rpc: preparation.client),
            signer: Signer(validator: PreparationValidator(rpc: signing.client),
                           store: store ?? SigningRecoveryStore(recovery: fixture.recovery)),
            submitter: Submitter(rpcs: [HTTPResponses.sending().client]),
            confirmer: Confirmer(rpc: confirmation.client(socket: { sockets.connect($0) }))
        )
        let keypad = PaymentModel(tokens: [sol], currencyCode: "USD")
        keypad.press(.digit(1))
        let portfolio = RecordingPortfolio()
        let model = SendModel(payment: keypad,
                              recipient: PaymentRecipient(address: fixture.transfer.accounts[1].address, name: "Bruno"),
                              account: fixture.account, transactions: transactions, portfolio: portfolio)
        return Payment(model: model, keypad: keypad, portfolio: portfolio, preparation: preparation, sockets: sockets)
    }

    /// A successful simulation without balances.
    private static let success = SimulateTransaction.Value(
        error: nil, logs: ["Program completed"], unitsConsumed: 150, loadedAccountsDataSize: 256, fee: networkFee,
        replacementBlockhash: nil, preBalances: nil, postBalances: nil, preTokenBalances: nil, postTokenBalances: nil
    )

    /// Creates a failed simulation without balances.
    /// - Parameter error: The execution error.
    /// - Returns: The execution.
    private static func execution(error: TransactionError) -> SimulateTransaction.Value {
        SimulateTransaction.Value(error: error, logs: [], unitsConsumed: 150, loadedAccountsDataSize: 256,
                                  fee: networkFee, replacementBlockhash: nil, preBalances: nil, postBalances: nil,
                                  preTokenBalances: nil, postTokenBalances: nil)
    }

    /// Wraps the payment's status in a status read at slot 2,000.
    /// - Parameters:
    ///   - commitment: The status's commitment at slot 405, or `nil` when the provider has no status.
    ///   - error: The landed payment's execution error, or `nil` when it succeeded.
    /// - Returns: A one-signature status read.
    private static func status(_ commitment: Commitment?, error: TransactionError? = nil)
        -> GetSignatureStatuses.Response {
        let status = commitment.map {
            GetSignatureStatuses.Status(slot: 405, confirmations: nil, error: error, confirmationStatus: $0)
        }
        return GetSignatureStatuses.Response(context: Context(slot: 2_000), value: [status])
    }

    /// Reviews the payment, as the sheet does when it opens.
    /// - Parameter model: The model.
    /// - Throws: A test failure when no review shows.
    private static func review(_ model: SendModel) async throws {
        model.prepareReview()
        await model.run(model.attempt)
        try #require(model.canApprove)
    }

    /// Counts the simulations sent so far.
    /// - Parameter responses: The local responses that recorded the requests.
    /// - Returns: The number of `simulateTransaction` requests.
    /// - Throws: A test prerequisite error for a request without a method.
    private static func simulations(of responses: HTTPResponses) async throws -> Int {
        try await responses.requests.count { try $0.rpcMethod == "simulateTransaction" }
    }
}
