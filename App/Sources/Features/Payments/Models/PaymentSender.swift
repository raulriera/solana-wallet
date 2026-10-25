import RPC

/// What a window needs to send payments: its account on its network, the shared transactions, and the portfolio that
/// reads the balances again after a payment lands.
@MainActor
struct PaymentSender {
    /// The window's account, which pays.
    let account: Account
    /// The window's network.
    let network: Network
    /// The transactions that every window sends, watches, and records.
    let transactions: TransactionStore
    /// The window's portfolio, on the window's network.
    let portfolio: any PortfolioCoordinating

    /// Starts a payment of the amount typed now, with what its review asks the person to check about the recipient.
    /// - Parameters:
    ///   - payment: The keypad's payment.
    ///   - recipient: Who the payment goes to.
    ///   - context: The person's own history, which the review's checks compare the recipient with.
    /// - Returns: The payment, before its review is simulated.
    /// - Throws: The error of creating the network's transaction coordinator.
    func send(_ payment: PaymentModel, to recipient: PaymentRecipient, in context: RecipientContext) throws
        -> SendModel {
        SendModel(payment: payment, recipient: recipient,
                  warnings: RecipientClassifier.review.warnings(for: recipient.address, in: context), account: account,
                  coordinator: try transactions.coordinator(for: network), transactions: transactions,
                  portfolio: portfolio)
    }
}
