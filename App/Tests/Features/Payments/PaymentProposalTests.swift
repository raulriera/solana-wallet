@testable import RPC
import Testing
import Transactions
@testable import widgets

/// Checks how a payment's proposal reads its simulations through the real transaction coordinator, with local
/// responses.
@MainActor
struct PaymentProposalTests {
    /// A successful simulation of a SOL payment costs its network fee alone and records the payment.
    /// - Throws: A fixture error.
    @Test
    func `A SOL payment costs its network fee and records the payment`() async throws {
        let payment = try LocalPaymentReview()
        let proposal = payment.model.proposal

        let proposed = try await Self.simulate(proposal, in: payment)

        #expect(proposed.review == PaymentProposal.Review(networkFee: 10_000, accountDeposit: nil))
        #expect(proposed.kind == .payment(recipient: proposal.recipient.address, mint: nil, units: 1_000_000_000))
        #expect(proposed.settling == nil)
    }

    /// A simulation that runs out of SOL can't be sent; another execution failure is a preparation failure.
    /// - Parameters:
    ///   - error: The simulated execution error.
    ///   - expected: The payment's error.
    /// - Throws: A fixture error.
    @Test(arguments: [
        (TransactionError(name: "InsufficientFundsForFee", details: nil), SendError.notEnoughSOL),
        (TransactionError(name: "InstructionError", details: .array([.integer(0), .object(["Custom": .integer(6001)])])),
         .preparationFailed),
    ])
    func `A failed simulation throws the payment's error`(error: TransactionError, expected: SendError) async throws {
        let payment = try LocalPaymentReview(simulation: LocalPaymentReview.execution(error: error))

        await #expect(throws: expected) { try await Self.simulate(payment.model.proposal, in: payment) }
    }

    /// Simulates a proposal from the fixture account with the local coordinator, as its review does.
    /// - Parameters:
    ///   - proposal: The payment's proposal.
    ///   - payment: The local responses behind the review.
    /// - Returns: The simulation and its review.
    /// - Throws: The proposal's error.
    private static func simulate(_ proposal: PaymentProposal, in payment: LocalPaymentReview) async throws
        -> ProposedTransaction<PaymentProposal.Review> {
        try await proposal.simulate((), with: payment.transactions.coordinator(for: .devnet), from: payment.account)
    }
}
