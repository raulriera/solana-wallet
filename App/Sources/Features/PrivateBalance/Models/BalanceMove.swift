import Foundation
import Privacy
import RPC

/// A move of an account's asset between its public and private balances, or to a recipient's private balance, with the amount being typed.
@MainActor
struct BalanceMove: Identifiable {
    let direction: BalanceMoveProposal.Direction
    /// The pool's asset of the token that moves.
    let privateAsset: PrivateAsset
    /// The amount being typed.
    let payment: PaymentModel
    let account: Account
    let network: Network
    let balances: any PrivateBalancing
    let transactions: TransactionStore

    var id: ObjectIdentifier { ObjectIdentifier(payment) }

    /// Creates a move with an empty amount.
    ///
    /// - Parameters:
    ///   - direction: Which balance the asset leaves, and which one it reaches.
    ///   - token: The asset that moves, whose balance is the most that the move can take.
    ///   - privateAsset: The pool's asset of the token.
    ///   - account: The account whose asset moves.
    ///   - network: The network that the asset moves on.
    ///   - balances: The private balances of every account.
    ///   - transactions: The transaction store.
    init(
        direction: BalanceMoveProposal.Direction,
        token: PaymentToken,
        privateAsset: PrivateAsset,
        account: Account,
        network: Network,
        balances: any PrivateBalancing,
        transactions: TransactionStore
    ) {
        payment = PaymentModel(tokens: [token], currencyCode: "USD", source: direction.source)
        self.direction = direction
        self.privateAsset = privateAsset
        self.account = account
        self.network = network
        self.balances = balances
        self.transactions = transactions
    }

    /// Creates the review of the typed amount.
    ///
    /// - Returns: The move's review.
    /// - Throws: ``PrivateBalanceError/preparationFailed`` for an amount that can't be sent, or the error of
    ///   creating the network's transaction coordinator.
    func review() throws -> TransactionReviewModel<BalanceMoveProposal> {
        guard let sent = payment.sent else { throw PrivateBalanceError.preparationFailed }
        let proposal = BalanceMoveProposal(
            direction: direction,
            asset: payment.token.asset,
            privateAsset: privateAsset,
            sent: sent,
            balances: balances
        )
        return try TransactionReviewModel(proposal, from: account, on: network, transactions: transactions)
    }
}
