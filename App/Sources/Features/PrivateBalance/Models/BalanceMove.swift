import Foundation
import Portfolio
import RPC

/// A move of an account's SOL between its public and private balances, with the amount being typed.
@MainActor
struct BalanceMove: Identifiable {
    let direction: BalanceMoveProposal.Direction
    /// The amount being typed, in SOL.
    let payment: PaymentModel
    let account: Account
    let network: Network
    let balances: any PrivateBalancing
    let transactions: TransactionStore

    var id: ObjectIdentifier { ObjectIdentifier(payment) }

    /// Creates a move with an empty amount.
    ///
    /// - Parameters:
    ///   - direction: Which balance the SOL leaves, and which one it reaches.
    ///   - account: The account whose SOL moves.
    ///   - network: The network that the SOL moves on.
    ///   - spendableLamports: The most SOL that the move can take, in lamports.
    ///   - balances: The private balances of every account.
    ///   - transactions: The transaction store.
    init(direction: BalanceMoveProposal.Direction, account: Account, network: Network, spendableLamports: UInt64,
         balances: any PrivateBalancing, transactions: TransactionStore) {
        let spendable = Amount(lamports: spendableLamports)
        let sol = PaymentToken(mint: nil, symbol: "SOL", balance: Decimal(spendable), price: nil,
                               decimals: Int(spendable.decimals))
        let source: PaymentModel.Source = switch direction {
        case .toPrivate: .publicBalance
        case .toPublic: .privateBalance
        }
        payment = PaymentModel(tokens: [sol], currencyCode: "USD", source: source)
        self.direction = direction
        self.account = account
        self.network = network
        self.balances = balances
        self.transactions = transactions
    }

    /// Creates the review of the typed amount.
    ///
    /// - Returns: The move's review.
    /// - Throws: The error of creating the network's transaction coordinator.
    func review() throws -> TransactionReviewModel<BalanceMoveProposal> {
        let proposal = BalanceMoveProposal(direction: direction, amount: payment.amount, balances: balances)
        return try TransactionReviewModel(proposal, from: account, on: network, transactions: transactions)
    }
}
