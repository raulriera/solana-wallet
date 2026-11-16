import Foundation
import Privacy
import Testing
import Transactions
@testable import RPC
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct BalanceMoveProposalTests {
    private static let rateLimit = RPCError.http(statusCode: 429, retryAfter: "3")

    private nonisolated static let assets = [PrivateAsset.nativeSOL, .token(.devnetUSDC)]

    @Test(arguments: Self.assets)
    func `Reviewing a deposit shows its network fee`(asset: PrivateAsset) async throws {
        let deposit = try await LocalBalanceMove.deposit(of: asset)
        let model = deposit.model

        model.prepareReview()
        deposit.move.payment.press(.digit(5))
        await model.run(model.attempt)

        #expect(model.review == BalanceMoveProposal.Review(networkFee: LocalBalanceMove.networkFee,
                                                           registrationFee: nil, privacyFee: nil, pendingChange: nil,
                                                           accountDeposit: nil))
        let sent = model.proposal.sent
        #expect(sent.amount == LocalBalanceMove.amount)
        #expect(model.error == nil)
        #expect(model.canApprove)
    }

    @Test(arguments: Self.assets)
    func `A first deposit shows the registration fee`(asset: PrivateAsset) async throws {
        let deposit = try await LocalBalanceMove.deposit(of: asset, registered: false)
        let model = deposit.model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.review == BalanceMoveProposal.Review(networkFee: LocalBalanceMove.networkFee,
                                                           registrationFee: LocalBalanceMove.registrationRent,
                                                           privacyFee: nil, pendingChange: nil, accountDeposit: nil))
        #expect(model.error == nil)
    }

    @Test(arguments: [
        (
            PrivateAsset.nativeSOL, TransactionError(name: "InsufficientFundsForFee", details: nil), [String](),
            PrivateBalanceError.insufficientPublicBalance
        ),
        (
            .nativeSOL,
            TransactionError(
                name: "InstructionError",
                details: .array([.integer(0), .object(["Custom": .integer(1)])])
            ),
            ["Transfer: insufficient lamports 0, need 1000000000"], .insufficientPublicBalance
        ),
        (
            .nativeSOL,
            TransactionError(
                name: "InstructionError",
                details: .array([.integer(1), .object(["Custom": .integer(6001)])])
            ),
            ["Program failed: custom program error: 0x1771"], .preparationFailed
        ),
        (
            .token(.devnetUSDC), TransactionError(name: "InsufficientFundsForFee", details: nil), [],
            .insufficientPublicBalanceForFees
        ),
    ])
    func `A failed simulation shows its error without a review`(
        asset: PrivateAsset,
        error: TransactionError,
        logs: [String],
        expected: PrivateBalanceError
    )
        async throws
    {
        let deposit = try await LocalBalanceMove.deposit(
            of: asset,
            simulation: .failure(
                error,
                logs: logs,
                fee: LocalBalanceMove.networkFee
            )
        )
        let model = deposit.model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.error == expected)
        #expect(model.review == nil)
        #expect(!model.canApprove)
    }

    @Test
    func `A preparation error reaches the review unchanged`() async throws {
        let deposit = try await LocalBalanceMove.deposit(of: .nativeSOL, provider: try PrivateBalanceFixtures.customRPC())
        let model = deposit.model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.error == .unavailable)
        #expect(model.review == nil)
        #expect(try await deposit.preparation.simulations() == 0)
    }

    @Test
    func `Approving sends the deposit and leaves it pending`() async throws {
        let deposit = try await LocalBalanceMove.deposit(of: .nativeSOL, statuses: [.status(.finalized)])
        try await deposit.model.runReview()

        let record = try await deposit.model.runApproval()

        #expect(record.kind == .privateDeposit)
        #expect(deposit.model.submission?.network == .devnet)
        #expect(try await deposit.transactions.watch(record.id, for: record.key) == .succeeded)
        #expect(deposit.model.outcome == .succeeded)
        #expect(try await deposit.balances.refresh(deposit.account, on: .devnet)
            == .balance(available: 0, pending: LocalBalanceMove.amount, of: .nativeSOL))
        #expect(deposit.model.error == nil)
        await deposit.sockets.waitUntilClosed()
    }

    @Test
    func `A stopped watch keeps the review waiting until a later watch settles it`() async throws {
        let refusal = Self.rateLimit
        let sockets = SocketSequence { $0 == 0 ? SocketSequence.failing(with: refusal) : SocketSequence.watch() }
        let deposit = try await LocalBalanceMove.deposit(of: .nativeSOL, statuses: [.status(.finalized)], sockets: sockets)
        let model = deposit.model
        try await deposit.model.runReview()
        let record = try await deposit.model.runApproval()
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
            == .balance(available: 0, pending: LocalBalanceMove.amount, of: .nativeSOL))
        #expect(sockets.sockets.count == 2)
        await sockets.waitUntilClosed()
    }

    @Test(arguments: [(PrivateAsset.nativeSOL, UInt64(0)), (.token(.devnetUSDC), 0), (.token(.devnetUSDC), 1_488_440)],
          [UInt64(0), 3_000])
    func `Reviewing a withdrawal shows a privacy fee and an account deposit only when it has them`(
        withdrawn: (asset: PrivateAsset, accountDeposit: UInt64),
        privacyFee: UInt64
    )
        async throws
    {
        let withdrawal = try await LocalBalanceMove.withdrawal(of: withdrawn.asset, privacyFee: privacyFee,
                                                               accountDeposit: withdrawn.accountDeposit)
        let model = withdrawal.model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(withdrawal.move.payment.source == .privateBalance)
        let decimals: UInt8 = withdrawn.asset == .nativeSOL ? 9 : 6
        #expect(withdrawal.move.payment.token.balance == TokenAmount(amount: 2_000_000_000, decimals: decimals))
        #expect(model.review == BalanceMoveProposal.Review(
            networkFee: LocalBalanceMove.networkFee, registrationFee: nil,
            privacyFee: privacyFee > 0 ? privacyFee : nil,
            pendingChange: LocalBalanceMove.privateAmount - LocalBalanceMove.amount,
            accountDeposit: withdrawn.accountDeposit > 0 ? withdrawn.accountDeposit : nil
        ))
        #expect(model.error == nil)
    }

    @Test
    func `A withdrawal of a whole note has no pending change`() async throws {
        let withdrawal = try await LocalBalanceMove.withdrawal(of: .nativeSOL, privateAmount: LocalBalanceMove.amount)
        let model = withdrawal.model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(try #require(model.review).pendingChange == nil)
        #expect(model.error == nil)
    }

    @Test
    func `A withdrawal that the public balance can't pay for shows the fees error`() async throws {
        let failure = SimulateTransaction.Value.failure(TransactionError(name: "InsufficientFundsForFee", details: nil),
                                                        fee: LocalBalanceMove.networkFee)
        let withdrawal = try await LocalBalanceMove.withdrawal(of: .nativeSOL, simulation: failure)
        let model = withdrawal.model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.error == .insufficientPublicBalanceForFees)
        #expect(model.review == nil)
    }

    @Test
    func `Approving sends the withdrawal and keeps its change pending`() async throws {
        let withdrawal = try await LocalBalanceMove.withdrawal(of: .nativeSOL, statuses: [.status(.finalized)])
        try await withdrawal.model.runReview()

        let record = try await withdrawal.model.runApproval()

        #expect(record.kind == .privateWithdrawal)
        #expect(try await withdrawal.transactions.watch(record.id, for: record.key) == .succeeded)
        #expect(withdrawal.model.outcome == .succeeded)
        #expect(try await withdrawal.balances.refresh(withdrawal.account, on: .devnet)
            == .balance(available: 0, pending: LocalBalanceMove.privateAmount - LocalBalanceMove.amount, of: .nativeSOL))
        #expect(withdrawal.model.error == nil)
        await withdrawal.sockets.waitUntilClosed()
    }
}
