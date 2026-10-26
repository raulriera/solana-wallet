import RPC

/// What a window needs to send payments: its account on its network and the shared transactions.
@MainActor
struct PaymentSender {
    /// The window's account, which pays.
    let account: Account
    /// The window's network.
    let network: Network
    /// The transactions that every window sends, watches, and records.
    let transactions: TransactionStore

    /// Starts the review of a payment of the amount typed now, with what it asks the person to check about the
    /// recipient.
    /// - Parameters:
    ///   - amount: The amount as typed now.
    ///   - recipient: Who the payment goes to.
    ///   - context: The person's own history, which the review's checks compare the recipient with.
    /// - Returns: The payment's review, before it's simulated.
    /// - Throws: The error of creating the network's transaction coordinator.
    func review(_ amount: PaymentAmount, to recipient: PaymentRecipient, in context: RecipientContext) throws
        -> TransactionReviewModel<PaymentProposal> {
        let proposal = PaymentProposal(amount: amount, recipient: recipient,
                                       warnings: RecipientClassifier.review.warnings(for: recipient.address,
                                                                                     in: context))
        return try TransactionReviewModel(proposal, from: account, on: network, transactions: transactions)
    }
}
