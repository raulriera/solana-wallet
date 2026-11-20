import RPC

/// A sender of payments from an account on a network.
@MainActor
struct PaymentSender {
    /// The account that pays.
    let account: Account
    let network: Network
    let transactions: TransactionStore
    /// The store that keeps the recipients of the payments that succeed.
    let recents: RecentPaymentStore

    /// Creates the review of the typed payment to a recipient.
    ///
    /// - Parameters:
    ///   - payment: The payment being typed.
    ///   - recipient: The recipient of the payment.
    ///   - context: The context to check the recipient against.
    /// - Returns: The payment's review, before it's simulated.
    /// - Throws: ``SendError/preparationFailed`` for an amount that can't be sent, or an error creating the
    ///   network's transaction coordinator.
    func review(_ payment: PaymentModel, to recipient: PaymentRecipient, in context: RecipientContext) throws
        -> TransactionReviewModel<PaymentProposal> {
        guard let sent = payment.sent else { throw SendError.preparationFailed }
        let proposal = PaymentProposal(asset: payment.token.asset, sent: sent, value: payment.value,
                                       currencyCode: payment.currencyCode, recipient: recipient,
                                       warnings: RecipientClassifier.review.warnings(for: recipient.address,
                                                                                     in: context),
                                       recents: recents)
        return try TransactionReviewModel(proposal, from: account, on: network, transactions: transactions)
    }
}
