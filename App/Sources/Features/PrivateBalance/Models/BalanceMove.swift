import Foundation
import Portfolio
import RPC

/// One open move of an account's SOL between its public balance and its own private balance: the amount being typed,
/// and what the move needs to start its review.
@MainActor
struct BalanceMove: Identifiable {
    /// Which balance the SOL leaves, and which one it reaches.
    let direction: BalanceMoveProposal.Direction
    /// The amount being typed on the keypad, in SOL from the balance that it leaves.
    let payment: PaymentModel
    /// The account whose SOL moves; it signs and pays.
    let account: Account
    /// The window's network.
    let network: Network
    /// The private balances of every account, which prepare the move and record its outcome.
    let balances: any PrivateBalancing
    /// The transactions that every window sends, watches, and records.
    let transactions: TransactionStore

    /// The move's amount, which identifies it as long as its keypad shows.
    var id: ObjectIdentifier { ObjectIdentifier(payment) }

    /// Starts an empty amount of SOL from the balance that the SOL leaves.
    /// - Parameters:
    ///   - direction: Which balance the SOL leaves, and which one it reaches.
    ///   - account: The account whose SOL moves between its balances.
    ///   - network: The window's network.
    ///   - spendableLamports: The SOL that the amount can take from the balance that it leaves, in lamports.
    ///   - balances: The private balances of every account.
    ///   - transactions: The shared transactions, which simulate, send, record, and watch the move.
    init(direction: BalanceMoveProposal.Direction, account: Account, network: Network, spendableLamports: UInt64,
         balances: any PrivateBalancing, transactions: TransactionStore) {
        let spendable = Amount(lamports: spendableLamports)
        let sol = PaymentToken(mint: nil, symbol: "SOL", balance: Decimal(spendable), price: nil,
                               decimals: Int(spendable.decimals))
        let source: PaymentModel.Source = switch direction {
        case .toPrivate: .publicBalance
        case .toPublic: .privateBalance
        }
        // Without a price, the keypad types SOL and never shows the currency.
        payment = PaymentModel(tokens: [sol], currencyCode: "USD", source: source)
        self.direction = direction
        self.account = account
        self.network = network
        self.balances = balances
        self.transactions = transactions
    }

    /// Starts the review of the amount typed now.
    /// - Returns: The move's review, before it's proved and simulated.
    /// - Throws: The error of creating the network's transaction coordinator.
    func review() throws -> TransactionReviewModel<BalanceMoveProposal> {
        let proposal = BalanceMoveProposal(direction: direction, amount: payment.amount, balances: balances)
        return try TransactionReviewModel(proposal, from: account, on: network, transactions: transactions)
    }
}
