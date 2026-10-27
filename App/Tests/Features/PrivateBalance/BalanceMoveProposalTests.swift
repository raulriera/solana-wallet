import Foundation
@testable import RPC
import Testing
import Transactions
@testable import widgets

/// Verifies moves of SOL between an account's balances, deposits and withdrawals, through the shared review: their
/// reviews, sending, and settling through the real private balances and transaction coordinator, with local responses
/// and sockets.
///
/// Each move types 1 SOL: a deposit from a public balance of 2 SOL, a withdrawal from a private note of 2 SOL to the
/// same public balance. Every simulation reports a 10,000-lamport network fee.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct BalanceMoveProposalTests {
    /// A provider's rate limit.
    private static let rateLimit = RPCError.http(statusCode: 429, retryAfter: "3")

    /// Reviewing a registered account's typed amount shows the network fee, without a registration fee, and freezes
    /// the amount as typed.
    @Test
    func `Reviewing a deposit shows its network fee`() async throws {
        let deposit = try await LocalBalanceMove.deposit()
        let model = deposit.model

        model.prepareReview()
        deposit.move.payment.press(.digit(5))
        await model.run(model.attempt)

        #expect(model.review == BalanceMoveProposal.Review(networkFee: LocalBalanceMove.networkFee,
                                                           registrationFee: nil, privacyFee: nil, pendingChange: nil))
        #expect(model.proposal.amount.units == LocalBalanceMove.lamports)
        #expect(model.error == nil)
        #expect(model.canApprove)
    }

    /// An unregistered account's first deposit shows the registration fee: what the payer's SOL pays beyond the
    /// deposit and the network fee.
    @Test
    func `A first deposit shows the registration fee`() async throws {
        let deposit = try await LocalBalanceMove.deposit(registered: false)
        let model = deposit.model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.review == BalanceMoveProposal.Review(networkFee: LocalBalanceMove.networkFee,
                                                           registrationFee: LocalBalanceMove.registrationRent,
                                                           privacyFee: nil, pendingChange: nil))
        #expect(model.error == nil)
    }

    /// A simulation that runs out of SOL is an insufficient public balance, and another execution failure is a
    /// preparation failure; neither shows a review.
    /// - Parameters:
    ///   - error: The simulated execution error.
    ///   - logs: The simulated program logs.
    ///   - expected: The review's error.
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
        let deposit = try await LocalBalanceMove.deposit(simulation: .failure(error, logs: logs,
                                                                              fee: LocalBalanceMove.networkFee))
        let model = deposit.model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.error == expected)
        #expect(model.review == nil)
        #expect(!model.canApprove)
    }

    /// A private-balance error from preparing the deposit reaches the review unchanged, and nothing is simulated.
    @Test
    func `A preparation error reaches the review unchanged`() async throws {
        let deposit = try await LocalBalanceMove.deposit(provider: .solana)
        let model = deposit.model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.error == .unavailable)
        #expect(model.review == nil)
        #expect(try await deposit.preparation.simulations() == 0)
    }

    /// Approving sends the reviewed deposit; once it lands, its record shows the outcome and the settling leaves the
    /// SOL pending in the private balance.
    @Test
    func `Approving sends the deposit and leaves it pending`() async throws {
        let deposit = try await LocalBalanceMove.deposit(statuses: [.status(.finalized)])
        try await deposit.model.runReview()

        let record = try await deposit.model.runApproval()

        #expect(record.kind == .privateDeposit(lamports: LocalBalanceMove.lamports))
        #expect(deposit.model.submission?.network == .devnet)
        // The watch returns once the settling recorded the deposit in the private balance.
        #expect(try await deposit.transactions.watch(record.id, for: record.key) == .succeeded)
        #expect(deposit.model.outcome == .succeeded)
        #expect(try await deposit.balances.refresh(deposit.account, on: .devnet)
            == .balance(available: 0, pending: LocalBalanceMove.lamports))
        #expect(deposit.model.error == nil)
        await deposit.sockets.waitUntilClosed()
    }

    /// A watch that a rate limit stops leaves the review waiting, without an error or a result; a later watch of the
    /// same record settles the deposit and shows the result.
    @Test
    func `A stopped watch keeps the review waiting until a later watch settles it`() async throws {
        let refusal = Self.rateLimit
        let sockets = SocketSequence { $0 == 0 ? SocketSequence.failing(with: refusal) : SocketSequence.watch() }
        let deposit = try await LocalBalanceMove.deposit(statuses: [.status(.finalized)], sockets: sockets)
        let model = deposit.model
        try await deposit.model.runReview()
        let record = try await deposit.model.runApproval()
        // The first watch ends with the rate limit, which only a caller of the watch reads.
        await #expect(throws: (any Error).self) { try await deposit.transactions.watch(record.id, for: record.key) }

        #expect(model.status == .pending)
        #expect(model.isSending)
        #expect(model.outcome == nil)
        #expect(model.error == nil)

        await deposit.transactions.resume()

        #expect(try await deposit.transactions.watch(record.id, for: record.key) == .succeeded)
        #expect(model.outcome == .succeeded)
        #expect(!model.isSending)
        #expect(try await deposit.balances.refresh(deposit.account, on: .devnet)
            == .balance(available: 0, pending: LocalBalanceMove.lamports))
        #expect(sockets.sockets.count == 2)
        await sockets.waitUntilClosed()
    }

    /// A withdrawal types from the available private balance, and its review shows the network fee and the spent
    /// note's change, with the privacy fee only when the simulation charges one.
    /// - Parameter privacyFee: The pool's fee that the simulation charges the payer, in lamports.
    @Test(arguments: [UInt64(0), 3_000])
    func `Reviewing a withdrawal shows a privacy fee only when it has one`(privacyFee: UInt64) async throws {
        let withdrawal = try await LocalBalanceMove.withdrawal(privacyFee: privacyFee)
        let model = withdrawal.model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(withdrawal.move.payment.source == .privateBalance)
        #expect(withdrawal.move.payment.token.balance == 2)
        #expect(model.review == BalanceMoveProposal.Review(
            networkFee: LocalBalanceMove.networkFee, registrationFee: nil,
            privacyFee: privacyFee > 0 ? privacyFee : nil,
            pendingChange: LocalBalanceMove.privateLamports - LocalBalanceMove.lamports
        ))
        #expect(model.error == nil)
    }

    /// A withdrawal that spends a whole note returns no change, so nothing becomes pending.
    @Test
    func `A withdrawal of a whole note has no pending change`() async throws {
        let withdrawal = try await LocalBalanceMove.withdrawal(privateLamports: LocalBalanceMove.lamports)
        let model = withdrawal.model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(try #require(model.review).pendingChange == nil)
        #expect(model.error == nil)
    }

    /// A withdrawal's simulation that runs out of SOL means the public balance can't pay the fees, and no review shows.
    @Test
    func `A withdrawal that the public balance can't pay for shows the fees error`() async throws {
        let failure = SimulateTransaction.Value.failure(TransactionError(name: "InsufficientFundsForFee", details: nil),
                                                        fee: LocalBalanceMove.networkFee)
        let withdrawal = try await LocalBalanceMove.withdrawal(simulation: failure)
        let model = withdrawal.model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.error == .insufficientPublicBalanceForFees)
        #expect(model.review == nil)
    }

    /// Approving sends the reviewed withdrawal; once it lands, the settling leaves the spent note's change pending in
    /// the private balance.
    @Test
    func `Approving sends the withdrawal and keeps its change pending`() async throws {
        let withdrawal = try await LocalBalanceMove.withdrawal(statuses: [.status(.finalized)])
        try await withdrawal.model.runReview()

        let record = try await withdrawal.model.runApproval()

        #expect(record.kind == .privateWithdrawal(lamports: LocalBalanceMove.lamports))
        #expect(try await withdrawal.transactions.watch(record.id, for: record.key) == .succeeded)
        #expect(withdrawal.model.outcome == .succeeded)
        #expect(try await withdrawal.balances.refresh(withdrawal.account, on: .devnet)
            == .balance(available: 0, pending: LocalBalanceMove.privateLamports - LocalBalanceMove.lamports))
        #expect(withdrawal.model.error == nil)
        await withdrawal.sockets.waitUntilClosed()
    }
}
