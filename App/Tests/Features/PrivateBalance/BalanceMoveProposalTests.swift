import Foundation
import Privacy
import Testing
import Transactions
@testable import RPC
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct BalanceMoveProposalTests {
    private nonisolated static let assets = [PrivateAsset.nativeSOL, .token(.devnetUSDC)]

    @Test
    func `Reviewing a deposit shows its network fee`() async throws {
        let deposit = try await LocalBalanceMove.deposit(of: .nativeSOL)
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
            PrivateAsset.nativeSOL, TransactionError.insufficientFundsForFee, [String](),
            PrivateBalanceError.insufficientPublicBalance
        ),
        (
            .nativeSOL,
            TransactionError.instructionError(1, custom: 6001),
            ["Program failed: custom program error: 0x1771"], .preparationFailed
        ),
        (
            .token(.devnetUSDC), TransactionError.insufficientFundsForFee, [],
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
        #expect(record.outcome.network == .devnet)
        #expect(try await deposit.transactions.watch(record.id, for: record.key).status == .succeeded(slot: 405))
        #expect(deposit.model.outcome?.status == .succeeded(slot: 405))
        #expect(try await deposit.balances.refresh(deposit.account, on: .devnet)
            == .balance(available: 0, pending: LocalBalanceMove.amount, of: .nativeSOL))
        #expect(deposit.model.error == nil)
        await deposit.sockets.waitUntilClosed()
    }

    @Test(arguments: zip(
        [(PrivateAsset.nativeSOL, UInt64(0)), (.token(.devnetUSDC), 0), (.token(.devnetUSDC), 1_488_440)],
        [UInt64(0), 3_000, 3_000]
    ))
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
        #expect(withdrawal.move.payment.token.balance.amount == 2_000_000_000)
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

    @Test(arguments: [TransactionRecord.Kind.privateWithdrawal, .privatePayment])
    func `Approving a spend records it and keeps its change pending`(kind: TransactionRecord.Kind) async throws {
        let spend = if kind == .privatePayment {
            try await LocalBalanceMove.send(of: .nativeSOL, statuses: [.status(.finalized)])
        } else {
            try await LocalBalanceMove.withdrawal(of: .nativeSOL, statuses: [.status(.finalized)])
        }
        try await spend.model.runReview()

        let record = try await spend.model.runApproval()

        #expect(record.kind == kind)
        #expect(try await spend.transactions.watch(record.id, for: record.key).status == .succeeded(slot: 405))
        #expect(spend.model.outcome?.status == .succeeded(slot: 405))
        #expect(try await spend.balances.refresh(spend.account, on: .devnet)
            == .balance(available: 0, pending: LocalBalanceMove.privateAmount - LocalBalanceMove.amount, of: .nativeSOL))
        #expect(spend.model.error == nil)
        await spend.sockets.waitUntilClosed()
    }

    @Test
    func `Reviewing a send shows the privacy fee without the sent amount`() async throws {
        let send = try await LocalBalanceMove.send(of: .nativeSOL, privacyFee: 3_000)
        let model = send.model

        model.prepareReview()
        await model.run(model.attempt)

        #expect(model.review == BalanceMoveProposal.Review(
            networkFee: LocalBalanceMove.networkFee, registrationFee: nil, privacyFee: 3_000,
            pendingChange: LocalBalanceMove.privateAmount - LocalBalanceMove.amount, accountDeposit: nil
        ))
        #expect(model.error == nil)
    }

    @Test(arguments: [TransactionRecord.Kind.privatePayment, .privateWithdrawal])
    func `A merge is preliminary and shows the fees of every transaction that follows it`(
        kind: TransactionRecord.Kind
    ) async throws {
        let move = if kind == .privatePayment {
            try await LocalBalanceMove.send(of: .nativeSOL, privacyFee: 3_000)
        } else {
            try await LocalBalanceMove.withdrawal(of: .token(.devnetUSDC), privacyFee: 3_000)
        }
        let merge = try await Self.merge(of: move, following: 2)

        let proposed = try await move.model.proposal.simulate(merge, with: move.transactions.coordinator(for: .devnet),
                                                              from: move.account)

        #expect(proposed.kind == kind)
        #expect(proposed.followingTransactions == 2)
        #expect(proposed.review == BalanceMoveProposal.Review(
            networkFee: 3 * LocalBalanceMove.networkFee, registrationFee: nil, privacyFee: 9_000,
            pendingChange: LocalBalanceMove.privateAmount - LocalBalanceMove.amount, accountDeposit: nil
        ))
    }

    @Test(arguments: [(UInt64(25_999), PrivateBalanceError?.some(.insufficientPublicBalanceForFees)), (26_000, nil)])
    func `A merge needs public SOL for the fees of every transaction that follows it`(
        lamportsAfterMerge: UInt64, expected: PrivateBalanceError?
    ) async throws {
        let move = try await LocalBalanceMove.send(
            of: .nativeSOL, publicLamports: lamportsAfterMerge + LocalBalanceMove.networkFee + 3_000, privacyFee: 3_000
        )
        let merge = try await Self.merge(of: move, following: 2)
        let coordinator = try move.transactions.coordinator(for: .devnet)

        if let expected {
            await #expect(throws: expected) {
                try await move.model.proposal.simulate(merge, with: coordinator, from: move.account)
            }
        } else {
            await #expect(throws: Never.self) {
                try await move.model.proposal.simulate(merge, with: coordinator, from: move.account)
            }
        }
    }

    @Test(arguments: Self.assets)
    func `A deposit that merges notes shows what its transaction pays beyond the deposit as the privacy fee`(
        asset: PrivateAsset
    ) async throws {
        let deposit = try await LocalBalanceMove.deposit(of: asset, registered: false)
        let send = try await LocalBalanceMove.send(of: asset)
        let merge = try #require(try await send.model.proposal.prepare(from: send.account, on: .devnet).effect.spend)
        let prepared = try await deposit.model.proposal.prepare(from: deposit.account, on: .devnet)
        let mergedDeposit = PreparedPrivateTransaction(
            instructions: prepared.instructions, account: prepared.account, network: prepared.network,
            effect: .mergedDeposit(LocalBalanceMove.amount, of: asset, merge: merge), registers: false,
            authorities: prepared.authorities
        )

        let proposed = try await deposit.model.proposal.simulate(
            mergedDeposit, with: deposit.transactions.coordinator(for: .devnet), from: deposit.account
        )

        #expect(proposed.kind == .privateDeposit)
        #expect(proposed.followingTransactions == 0)
        #expect(proposed.review == BalanceMoveProposal.Review(
            networkFee: LocalBalanceMove.networkFee, registrationFee: nil, privacyFee: LocalBalanceMove.registrationRent,
            pendingChange: nil, accountDeposit: nil
        ))
    }

    @Test(arguments: [false, true])
    func `A send checks the recipient against the person's history`(paid: Bool) throws {
        let recipient = PaymentRecipient(address: try SigningFixture().transfer.accounts[1].address, name: nil)
        let paidAddresses: Set<Address> = paid ? [recipient.address] : []
        let context = RecipientContext(knownAddresses: Array(paidAddresses), paidAddresses: paidAddresses)

        let direction = BalanceMoveProposal.Direction.send(to: recipient, in: context)

        #expect(direction == .toRecipient(recipient, warnings: paid ? [] : [.firstPayment]))
    }

    private static func merge(of move: LocalBalanceMove, following: Int) async throws -> PreparedPrivateTransaction {
        let prepared = try await move.model.proposal.prepare(from: move.account, on: .devnet)
        let spend = try #require(prepared.effect.spend)
        return PreparedPrivateTransaction(
            instructions: prepared.instructions, account: prepared.account, network: prepared.network,
            effect: .merge(spend, following: following), registers: prepared.registers,
            authorities: prepared.authorities
        )
    }
}
