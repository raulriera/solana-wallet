import RPC

nonisolated extension SimulateTransaction.Value {
    /// Whether the simulated execution failed because the payer's SOL didn't cover it: its fee, the rent of an account
    /// it creates, or a transfer, as the System Program logs when it runs out of lamports.
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
