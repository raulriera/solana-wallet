import RPC

/// Opens a move of the account's SOL between its balances from the private balance's rows, the way SwiftUI's `dismiss`
/// acts for the view that reads it.
struct PrivateBalanceMoveAction {
    /// The Portfolio tab's private-balance workflows, which open the move.
    let model: PrivateBalanceModel
    /// The private balance of every account on every network, which prepares the move.
    let privateBalances: PrivateBalanceStore
    /// The account whose SOL moves.
    let account: Account
    /// The network the SOL moves on.
    let network: Network
    /// The account's public SOL, in lamports, which a deposit can add.
    let publicLamports: UInt64

    /// Opens a move in one direction; a withdrawal opens only while some private SOL is available.
    /// - Parameter direction: Which balance the SOL leaves, and which one it reaches.
    func callAsFunction(_ direction: BalanceMoveProposal.Direction) {
        model.open(direction, publicLamports: publicLamports, in: privateBalances, for: account, on: network)
    }
}
