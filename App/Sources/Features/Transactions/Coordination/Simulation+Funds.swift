import RPC
import Transactions

nonisolated extension Simulation {
    /// Whether the transaction can't run for lack of SOL.
    ///
    /// It lacks SOL when its fee payer can't pay the fee or rent, or when the System program logs missing lamports.
    var lacksFunds: Bool {
        switch executionError {
        case nil: false
        case .insufficientFunds(let account)? where account == transaction.feePayer: true
        case .insufficientFundsForRent(let account)?: account == transaction.feePayer
        case .insufficientFunds?, .program?, .expired?, .other?:
            diagnostics.value.logs?.contains { $0.contains("Transfer: insufficient lamports") } == true
        }
    }

    /// Whether the transaction can't run because it would open an account other than its fee payer's with less than
    /// its rent-exempt minimum.
    var opensAccountBelowRent: Bool {
        guard case .insufficientFundsForRent(let account)? = executionError else { return false }
        return account != transaction.feePayer
    }
}
