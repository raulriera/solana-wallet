import RPC

nonisolated extension SimulateTransaction.Value {
    /// Whether the simulation failed because the payer lacked SOL for its fee, rent, or a transfer.
    var lacksFunds: Bool {
        guard let error else { return false }
        switch error.name {
        case "InsufficientFundsForFee":
            return true
        case "InsufficientFundsForRent":
            return error.accountIndex == 0
        default:
            return logs?.contains { $0.contains("Transfer: insufficient lamports") } == true
        }
    }

    /// Whether the simulation failed because it would open an account other than the payer's with less than its
    /// rent-exempt minimum.
    var opensAccountBelowRent: Bool {
        guard let error, error.name == "InsufficientFundsForRent" else { return false }
        return error.accountIndex != 0
    }
}

private nonisolated extension TransactionError {
    var accountIndex: UInt64? {
        guard case .object(let fields) = details, case .integer(let index) = fields["account_index"] else { return nil }
        return index
    }
}
