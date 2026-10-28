/// Opens a move of the account's SOL between its balances from the private balance's rows, the way SwiftUI's `dismiss`
/// acts for the view that reads it.
struct PrivateBalanceMoveAction {
    /// The window's private balance, which opens the move.
    let model: PrivateBalanceModel
    /// The window's account, whose SOL moves.
    let account: Account
    /// The account's public SOL, in lamports, which a deposit can add.
    let publicLamports: UInt64

    /// Opens a move in one direction; a withdrawal opens only while some private SOL is available.
    /// - Parameter direction: Which balance the SOL leaves, and which one it reaches.
    func callAsFunction(_ direction: BalanceMoveProposal.Direction) {
        model.open(direction, publicLamports: publicLamports, for: account)
    }
}
