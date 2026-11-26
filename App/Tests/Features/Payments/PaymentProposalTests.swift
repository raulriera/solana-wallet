import Foundation
import Testing
import Transactions
import Wallet
@testable import RPC
@testable import widgets

@MainActor
struct PaymentProposalTests {
    @Test(arguments: [
        (basisPoints: UInt16(250), maximum: UInt64(1_000_000), shown: UInt64?(25)),
        (basisPoints: 0, maximum: 0, shown: nil),
    ])
    func `A token payment's review shows the fee that the mint withholds`(
        basisPoints: UInt16, maximum: UInt64, shown: UInt64?
    ) async throws {
        let fixture = try SigningFixture()
        let tokens = try TokenTransferResponses(program: .token2022)
        let accounts = try tokens.http(destination: .initialized, transferFee: (basisPoints, maximum))
        let preparation = try HTTPResponses.preparation(fixture: fixture.preparation)
        let coordinator = try TransactionCoordinator.simulating(
            with: Preparer(rpc: preparation.client), configuration: fixture.configuration, accounts: accounts.client)
        let proposal = PaymentProposal(
            asset: .token(tokens.mint), sent: TokenAmount(amount: 1_000, decimals: 6), value: nil, currencyCode: "USD",
            recipient: PaymentRecipient(address: tokens.recipient, name: nil), warnings: [],
            recents: .inMemory())

        let sender = widgets.Account(id: UUID(), recoveryID: UUID(), address: tokens.sender, path: .solana)

        let proposed = try await proposal.simulate((), with: coordinator, from: sender)

        let review = PaymentProposal.Review(networkFee: 10_000, accountDeposit: nil,
                                            transferFee: shown.map { TokenAmount(amount: $0, decimals: 6) })
        #expect(proposed.review == review)
    }

    @Test(arguments: [
        (TransactionError.insufficientFundsForFee, SendError.notEnoughSOL),
        (TransactionError.insufficientFundsForRent(accountIndex: 1), .amountTooSmall),
        (TransactionError.instructionError(0, custom: 6001), .preparationFailed),
    ])
    func `A failed simulation throws the payment's error`(error: TransactionError, expected: SendError) async throws {
        let payment = try LocalPaymentReview(simulation: .failure(error, fee: LocalPaymentReview.networkFee))

        await #expect(throws: expected) { try await Self.simulate(payment.model.proposal, in: payment) }
    }

    @Test(arguments: [
        (TransactionOutcome.Status.succeeded(slot: 5), true),
        (.failed(slot: 5, .program(instruction: 0, code: 6001)), false),
        (.dropped, false),
    ])
    func `A payment's recipient becomes a recent payment only when the payment succeeds`(
        status: TransactionOutcome.Status, isRecent: Bool
    ) async throws {
        let payment = try LocalPaymentReview()
        let proposal = payment.model.proposal
        let settling = try #require(try await Self.simulate(proposal, in: payment).settling)

        await settling.settle(TransactionOutcome(signature: "signature", network: .devnet, lastValidBlockHeight: 550,
                                                 status: status))

        #expect(proposal.recents.payments(on: .devnet).map(\.address) == (isRecent ? [proposal.recipient.address] : []))
    }

    private static func simulate(_ proposal: PaymentProposal, in payment: LocalPaymentReview) async throws
        -> ProposedTransaction<PaymentProposal.Review> {
        try await proposal.simulate((), with: payment.transactions.coordinator(for: .devnet), from: payment.account)
    }
}
