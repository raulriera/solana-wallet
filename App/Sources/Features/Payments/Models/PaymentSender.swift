import RPC

/// A sender of payments from an account on a network.
@MainActor
struct PaymentSender {
    /// The account that pays.
    let account: Account
    let network: Network
    let transactions: TransactionStore

    /// Creates the review of a payment to a recipient.
    ///
    /// - Parameters:
    ///   - amount: The amount to pay.
    ///   - recipient: The recipient of the payment.
    ///   - context: The context to check the recipient against.
    /// - Returns: The payment's review, before it's simulated.
    /// - Throws: An error creating the network's transaction coordinator.
    func review(_ amount: PaymentAmount, to recipient: PaymentRecipient, in context: RecipientContext) throws
        -> TransactionReviewModel<PaymentProposal> {
        let proposal = PaymentProposal(amount: amount, recipient: recipient,
                                       warnings: RecipientClassifier.review.warnings(for: recipient.address,
                                                                                     in: context))
        return try TransactionReviewModel(proposal, from: account, on: network, transactions: transactions)
    }
}
