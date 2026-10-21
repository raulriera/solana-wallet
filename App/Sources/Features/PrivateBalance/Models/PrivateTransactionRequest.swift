import Transactions

/// A private-balance transaction that a person asks for, before its notes, keys, and proof.
nonisolated enum PrivateTransactionRequest: Equatable, Sendable {
    /// Moves public SOL from the account into its own private balance, in lamports.
    case deposit(UInt64)
    /// Sends SOL from the account's private balance to another account's private balance, in lamports.
    case send(UInt64, to: Address)
    /// Moves SOL from the account's private balance to a public address, in lamports.
    case withdraw(UInt64, to: Address)
    /// Moves SOL from the account's private balance into a new redeem code, in lamports, plus the public SOL that
    /// redeeming the code costs.
    case createCode(UInt64)
    /// Sweeps a redeem code's SOL into the account's private balance.
    case redeem(RedeemCode)
    /// Sweeps the SOL of one of the account's own redeem codes, at an index of its code root, back into its private
    /// balance.
    case takeBack(index: UInt32)
}
