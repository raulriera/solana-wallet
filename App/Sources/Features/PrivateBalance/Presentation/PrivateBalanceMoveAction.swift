import Portfolio
import RPC

/// Opens a move of a holding's asset between the account's balances.
struct PrivateBalanceMoveAction {
    let model: PrivateBalanceModel
    let privateBalances: PrivateBalanceStore
    let account: Account
    let network: Network
    let holding: Holding

    /// Opens a move in a direction.
    ///
    /// - Parameter direction: Which balance the asset leaves, and which one it reaches.
    func callAsFunction(_ direction: BalanceMoveProposal.Direction) {
        model.open(direction, of: holding, in: privateBalances, for: account, on: network)
    }
}
