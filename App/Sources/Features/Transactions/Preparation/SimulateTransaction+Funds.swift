import RPC

nonisolated extension SimulateTransaction.Value {
    /// Whether the simulation failed because the payer lacked SOL for its fee, rent, or a transfer.
    var lacksFunds: Bool {
        guard let error else { return false }
        switch error.name {
        case "InsufficientFundsForFee", "InsufficientFundsForRent":
            return true
        default:
            return logs?.contains { $0.contains("Transfer: insufficient lamports") } == true
        }
    }
}
