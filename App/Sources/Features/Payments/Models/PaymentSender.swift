import RPC

/// What a window needs to send payments: its account on its network, the network's transactions, and the portfolio
/// that reads the balances again after a payment lands.
@MainActor
struct PaymentSender {
    /// The window's account, which pays.
    let account: Account
    /// The window's network.
    let network: Network
    /// Every network's transaction coordinator, which windows share.
    let transactions: NetworkTransactions
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
                  transactions: try transactions.coordinator(for: network), portfolio: portfolio)
    }
}
