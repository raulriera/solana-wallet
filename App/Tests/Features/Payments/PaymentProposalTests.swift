import Testing
import Transactions
@testable import RPC
@testable import widgets

@MainActor
struct PaymentProposalTests {
    @Test
    func `A SOL payment costs its network fee and records the payment`() async throws {
        let payment = try LocalPaymentReview()
        let proposal = payment.model.proposal

        let proposed = try await Self.simulate(proposal, in: payment)

        #expect(proposed.review == PaymentProposal.Review(networkFee: 10_000, accountDeposit: nil))
        #expect(proposed.kind == .payment(recipient: proposal.recipient.address, mint: nil, units: 1_000_000_000))
        #expect(proposed.settling == nil)
    }

    @Test(arguments: [
        (TransactionError(name: "InsufficientFundsForFee", details: nil), SendError.notEnoughSOL),
        (TransactionError(name: "InsufficientFundsForRent", details: .object(["account_index": .integer(0)])),
         .notEnoughSOL),
        (TransactionError(name: "InsufficientFundsForRent", details: .object(["account_index": .integer(1)])),
         .amountTooSmall),
        (TransactionError(name: "InstructionError", details: .array([.integer(0), .object(["Custom": .integer(6001)])])),
         .preparationFailed),
    ])
    func `A failed simulation throws the payment's error`(error: TransactionError, expected: SendError) async throws {
        let payment = try LocalPaymentReview(simulation: .failure(error, fee: LocalPaymentReview.networkFee))

        await #expect(throws: expected) { try await Self.simulate(payment.model.proposal, in: payment) }
    }

    private static func simulate(_ proposal: PaymentProposal, in payment: LocalPaymentReview) async throws
        -> ProposedTransaction<PaymentProposal.Review> {
        try await proposal.simulate((), with: payment.transactions.coordinator(for: .devnet), from: payment.account)
    }
}
