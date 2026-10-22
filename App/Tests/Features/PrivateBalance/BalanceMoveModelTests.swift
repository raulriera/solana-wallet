import Foundation
import Privacy
@testable import RPC
import Testing
import Transactions
@testable import widgets

/// Verifies a move of public SOL into the private balance, a deposit: its review, sending, and watch through the real
/// private balances and transaction coordinator, with local responses and sockets.
///
/// Each model types 1 SOL from a public balance of 2 SOL; every simulation reports a 10,000-lamport network fee.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct BalanceMoveModelTests {
    /// The account's public SOL, in lamports.
    private static let publicLamports: UInt64 = 2_000_000_000
    /// The typed deposit, in lamports.
    private static let lamports: UInt64 = 1_000_000_000
    /// The network fee of every simulation, in lamports.
    private static let networkFee: UInt64 = 10_000
    /// The rent of the registry record that an account's first deposit creates, in lamports.
    private static let registrationRent: UInt64 = 1_823_520
    /// A provider's rate limit.
    private static let rateLimit = RPCError.http(statusCode: 429, retryAfter: "3")

    /// The local responses and connections behind a model.
    private struct Deposit {
        /// The model under test, with 1 SOL typed.
        let model: BalanceMoveModel
        /// The responses that answer the coordinator's preparation reads and simulations.
        let preparation: HTTPResponses
        /// The connections of the coordinator's watch.
        let sockets: SocketSequence
    }

    /// Reviewing a registered account's typed amount shows the lamports and network fee, without a registration fee.
    @Test
    func `Reviewing shows the amount and network fee`() async throws {
        let deposit = try await Self.deposit()
        let model = deposit.model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.review == BalanceMoveModel.Review(lamports: Self.lamports, networkFee: Self.networkFee,
                                                    registrationFee: nil))
        #expect(model.error == nil)
        #expect(model.attempt == nil)
    }

    /// An unregistered account's first deposit shows the registration fee: what the payer's SOL pays beyond the
    /// deposit and the network fee.
    @Test
    func `A first deposit shows the registration fee`() async throws {
        let model = try await Self.deposit(registered: false).model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.review == BalanceMoveModel.Review(lamports: Self.lamports, networkFee: Self.networkFee,
                                                    registrationFee: Self.registrationRent))
        #expect(model.error == nil)
    }

    /// A simulation that runs out of SOL is an insufficient public balance, and another execution failure is a
    /// preparation failure; neither shows a review.
    /// - Parameters:
    ///   - error: The simulated execution error.
    ///   - logs: The simulated program logs.
    ///   - expected: The model's error.
    @Test(arguments: [
        (TransactionError(name: "InsufficientFundsForFee", details: nil), [String](),
         PrivateBalanceError.insufficientPublicBalance),
        (TransactionError(name: "InstructionError", details: .array([.integer(0), .object(["Custom": .integer(1)])])),
         ["Transfer: insufficient lamports 0, need 1000000000"], .insufficientPublicBalance),
        (TransactionError(name: "InstructionError", details: .array([.integer(1), .object(["Custom": .integer(6001)])])),
         ["Program failed: custom program error: 0x1771"], .preparationFailed),
    ])
    func `A failed simulation shows its error without a review`(error: TransactionError, logs: [String],
                                                                 expected: PrivateBalanceError) async throws {
        let model = try await Self.deposit(simulation: Self.execution(error: error, logs: logs)).model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.error == expected)
        #expect(model.review == nil)
    }

    /// A private-balance error from preparing the deposit reaches the model unchanged, and nothing is simulated.
    @Test
    func `A preparation error reaches the model unchanged`() async throws {
        let deposit = try await Self.deposit(provider: .solana)
        let model = deposit.model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.error == .unavailable)
        #expect(model.review == nil)
        #expect(try await Self.simulations(of: deposit.preparation) == 0)
    }

    /// Approving signs and sends the reviewed deposit and watches it until it succeeds, which shows it pending in the
    /// private balance.
    @Test
    func `Approving sends the deposit and shows it pending`() async throws {
        let deposit = try await Self.deposit(statuses: [Self.status(.finalized)])
        let model = deposit.model
        try await Self.review(model)

        model.approve()
        await model.run(model.attempt)

        #expect(model.outcome == .succeeded)
        #expect(try #require(model.submission).network == .devnet)
        #expect(model.status == .balance(available: 0, pending: Self.lamports))
        #expect(model.error == nil)
        #expect(model.attempt == nil)
        await deposit.sockets.waitUntilClosed()
    }

    /// A dropped deposit can be tried again, which reviews the same amount anew.
    @Test
    func `Trying a dropped deposit again reviews the same amount`() async throws {
        // The epoch's block height is past the blockhash's last valid block height, 550, and no status exists.
        let deposit = try await Self.deposit(statuses: [Self.status(nil)], height: 600)
        let model = deposit.model
        try await Self.review(model)
        model.approve()
        await model.run(model.attempt)
        try #require(model.outcome == .dropped)
        await deposit.sockets.waitUntilClosed()

        model.tryAgain()
        let attempt = try #require(model.attempt)
        // The last review shows until the new one replaces it, and can't be approved meanwhile.
        #expect(model.isReviewing)
        #expect(!model.canApprove)
        await model.run(attempt)

        #expect(attempt.work == .review)
        #expect(model.review == BalanceMoveModel.Review(lamports: Self.lamports, networkFee: Self.networkFee,
                                                    registrationFee: nil))
        #expect(model.outcome == nil)
        #expect(model.submission == nil)
        #expect(try await Self.simulations(of: deposit.preparation) == 2)
    }

    /// A watch that a rate limit stops leaves the deposit unconfirmed with its receipt, and checking again settles it.
    @Test
    func `Checking an unconfirmed deposit again settles it`() async throws {
        let refusal = Self.rateLimit
        let sockets = SocketSequence { $0 == 0 ? SocketSequence.failing(with: refusal) : SocketSequence.watch() }
        let deposit = try await Self.deposit(statuses: [Self.status(.finalized)], sockets: sockets)
        let model = deposit.model
        try await Self.review(model)
        model.approve()
        await model.run(model.attempt)
        try #require(model.outcome == .unconfirmed)
        let submission = try #require(model.submission)

        model.checkAgain()
        await model.run(model.attempt)

        #expect(model.outcome == .succeeded)
        #expect(model.submission == submission)
        #expect(model.status == .balance(available: 0, pending: Self.lamports))
        #expect(sockets.sockets.count == 2)
        await sockets.waitUntilClosed()
    }

    /// A cancelled authentication uses up the review, so the model simulates the same deposit again and keeps
    /// reviewing, without an error or a submission.
    @Test
    func `A cancelled authentication keeps reviewing with a new review`() async throws {
        let store = SigningRecoveryStore(recovery: try PrivateBalanceFixtures.recovery(), error: CancellationError())
        let deposit = try await Self.deposit(store: store)
        let model = deposit.model
        try await Self.review(model)

        model.approve()
        await model.run(model.attempt)

        #expect(model.review == BalanceMoveModel.Review(lamports: Self.lamports, networkFee: Self.networkFee,
                                                    registrationFee: nil))
        #expect(model.error == nil)
        #expect(model.submission == nil)
        #expect(model.outcome == nil)
        #expect(await store.reads.count == 1)
        #expect(try await Self.simulations(of: deposit.preparation) == 2)
        model.approve()
        #expect(model.attempt?.work == .send)
    }

    /// Refreshing an open review simulates the same deposit again and keeps the same review, without an error.
    @Test
    func `Refreshing a review simulates it again`() async throws {
        let deposit = try await Self.deposit()
        let model = deposit.model
        try await Self.review(model)
        let review = model.review

        await model.refreshReview()

        #expect(model.review == review)
        #expect(model.error == nil)
        #expect(try await Self.simulations(of: deposit.preparation) == 2)
    }

    /// Refreshing waits while a step waits or runs, so it never replaces the review that the step uses.
    @Test
    func `Refreshing skips a review that's being sent`() async throws {
        let deposit = try await Self.deposit()
        let model = deposit.model
        try await Self.review(model)
        model.approve()

        await model.refreshReview()

        #expect(try await Self.simulations(of: deposit.preparation) == 1)
    }

    /// Leaving the review before sending returns to the amount, and the next review simulates the deposit again.
    @Test
    func `Leaving the review returns to the amount`() async throws {
        let deposit = try await Self.deposit()
        let model = deposit.model
        try await Self.review(model)

        model.isReviewing = false

        #expect(model.review == nil)
        #expect(!model.canApprove)
        try await Self.review(model)
        #expect(try await Self.simulations(of: deposit.preparation) == 2)
    }

    /// A sent deposit's result stays: leaving it doesn't clear the review.
    @Test
    func `A sent deposit keeps its review`() async throws {
        let deposit = try await Self.deposit(statuses: [Self.status(.finalized)])
        let model = deposit.model
        try await Self.review(model)
        model.approve()
        await model.run(model.attempt)

        model.isReviewing = false

        #expect(model.isReviewing)
        #expect(!model.canApprove)
        await deposit.sockets.waitUntilClosed()
    }

    /// Asking to review while a review waits for the scene's task keeps the waiting attempt.
    @Test
    func `Reviewing again while a review waits keeps it`() async throws {
        let model = try await Self.deposit().model
        model.prepareReview()
        let waiting = try #require(model.attempt)

        model.prepareReview()

        #expect(model.attempt == waiting)
    }

    /// Approving before a review exists starts nothing.
    @Test
    func `Approving without a review does nothing`() async throws {
        let model = try await Self.deposit().model

        model.approve()

        #expect(model.attempt == nil)
    }

    /// Creates a fixture account's deposit model on devnet, with 1 SOL typed, over private balances and a transaction
    /// coordinator that answer from local responses and sockets.
    /// - Parameters:
    ///   - registered: Whether the account registered its keys before; otherwise the deposit registers them.
    ///   - simulation: The simulated execution of every deposit, or `nil` for a success that reports the payer's SOL.
    ///   - provider: The selected provider of the private balances.
    ///   - store: The recovery storage that signing reads, or `nil` for the fixture recovery.
    ///   - statuses: The watch's status reads, in arrival order.
    ///   - height: The finalized block height of the watch's epoch reads.
    ///   - sockets: The watch's connections.
    /// - Returns: The model and the local responses and connections behind it.
    /// - Throws: A fixture error.
    private static func deposit(registered: Bool = true, simulation: SimulateTransaction.Value? = nil,
                                provider: ProviderSettings.Provider = .helius, store: SigningRecoveryStore? = nil,
                                statuses: [GetSignatureStatuses.Response] = [], height: UInt64 = 500,
                                sockets: SocketSequence = SocketSequence()) async throws -> Deposit {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let shielded = try record.shieldedAccount(for: account.address)
        let notes = registered
            ? StoredValue<PrivateBalances.Notes>([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
            : StoredValue<PrivateBalances.Notes>()
        let balances = PrivateBalances.inMemory(
            keys: StoredValue([account.address.value: record]), notes: notes,
            recovery: try PrivateBalanceFixtures.recoveryStore(),
            responses: HTTPResponses.privateNotes(registry: registered ? [] : [PrivateBalanceFixtures.unregistered],
                                                  outputTreeID: 1),
            provider: provider
        )
        var fixture = try SigningFixture()
        var instructions = [try ShieldedPool.deposit(lamports: lamports, from: account.address, to: shielded.recipient,
                                                     treeID: 1)]
        if !registered { instructions.insert(try shielded.register(paidBy: account.address), at: 0) }
        fixture.simulation = SimulateTransaction.Response(
            context: Context(slot: 402),
            value: try simulation ?? success(of: instructions, paidBy: account.address, fixture: fixture,
                                             registers: !registered)
        )
        let preparation = try HTTPResponses.preparation(fixture: fixture.preparation)
        let confirmation = try HTTPResponses.confirmation(
            statuses: statuses, epochs: [GetEpochInfo.Response(epoch: 1, absoluteSlot: 1_000, blockHeight: height)]
        )
        let signing = try HTTPResponses.signing()
        let transactions = TransactionCoordinator(
            rpc: preparation.client, configuration: fixture.configuration, preparer: Preparer(rpc: preparation.client),
            signer: Signer(validator: PreparationValidator(rpc: signing.client),
                           store: try store ?? SigningRecoveryStore(recovery: PrivateBalanceFixtures.recovery())),
            submitter: Submitter(rpcs: [HTTPResponses.sending().client]),
            confirmer: Confirmer(rpc: confirmation.client(socket: { sockets.connect($0) }))
        )
        let model = BalanceMoveModel(direction: .toPrivate, account: account, network: .devnet,
                                     spendableLamports: publicLamports, balances: balances, transactions: transactions)
        model.payment.press(.digit(1))
        return Deposit(model: model, preparation: preparation, sockets: sockets)
    }

    /// Creates a successful simulation of a deposit, whose payer pays the deposit, the network fee, and the rent of a
    /// registration.
    /// - Parameters:
    ///   - instructions: The deposit's instructions.
    ///   - payer: The account that pays.
    ///   - fixture: The blockhash and resource requests that the transaction compiles with.
    ///   - registers: Whether the deposit registers the account's keys.
    /// - Returns: The execution, with balances for every account of the compiled transaction.
    /// - Throws: A compilation error, which doesn't happen.
    private static func success(of instructions: [Instruction], paidBy payer: Address, fixture: SigningFixture,
                                registers: Bool) throws -> SimulateTransaction.Value {
        let message = try MessageBuilder().message(instructions: instructions, payer: payer,
                                                   recentBlockhash: fixture.blockhash.value.blockhash,
                                                   configuration: fixture.configuration)
        let others = try TransactionDecoder().decode(TransactionBuilder().simulationTransaction(for: message))
            .accounts.dropFirst().map { _ in UInt64(0) }
        let spent = lamports + networkFee + (registers ? registrationRent : 0)
        return SimulateTransaction.Value(error: nil, logs: ["Program completed"], unitsConsumed: 150,
                                         loadedAccountsDataSize: 256, fee: networkFee, replacementBlockhash: nil,
                                         preBalances: [publicLamports] + others,
                                         postBalances: [publicLamports - spent] + others,
                                         preTokenBalances: [], postTokenBalances: [])
    }

    /// Creates a failed simulation without balances.
    /// - Parameters:
    ///   - error: The execution error.
    ///   - logs: The program logs.
    /// - Returns: The execution.
    private static func execution(error: TransactionError, logs: [String]) -> SimulateTransaction.Value {
        SimulateTransaction.Value(error: error, logs: logs, unitsConsumed: 150, loadedAccountsDataSize: 256,
                                  fee: networkFee, replacementBlockhash: nil, preBalances: nil, postBalances: nil,
                                  preTokenBalances: nil, postTokenBalances: nil)
    }

    /// Wraps the deposit's status in a status read at slot 2,000.
    /// - Parameter commitment: The status's commitment at slot 405, or `nil` when the provider has no status.
    /// - Returns: A one-signature status read.
    private static func status(_ commitment: Commitment?) -> GetSignatureStatuses.Response {
        let status = commitment.map {
            GetSignatureStatuses.Status(slot: 405, confirmations: nil, error: nil, confirmationStatus: $0)
        }
        return GetSignatureStatuses.Response(context: Context(slot: 2_000), value: [status])
    }

    /// Reviews the typed amount, as the scene does before the person approves it.
    /// - Parameter model: The model.
    /// - Throws: A test failure when no review shows.
    private static func review(_ model: BalanceMoveModel) async throws {
        model.prepareReview()
        await model.run(model.attempt)
        try #require(model.review != nil)
    }

    /// Counts the simulations sent so far.
    /// - Parameter responses: The local responses that recorded the requests.
    /// - Returns: The number of `simulateTransaction` requests.
    /// - Throws: A test prerequisite error for a request without a method.
    private static func simulations(of responses: HTTPResponses) async throws -> Int {
        try await responses.requests.count { try $0.rpcMethod == "simulateTransaction" }
    }
}
