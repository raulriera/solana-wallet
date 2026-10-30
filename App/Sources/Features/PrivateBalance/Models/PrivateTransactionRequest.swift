import Transactions

/// A private-balance transaction that a person asks for.
nonisolated enum PrivateTransactionRequest: Equatable, Sendable {
    /// Moves public SOL, in lamports, into the account's private balance.
    case deposit(UInt64)
    /// Sends private SOL, in lamports, to another account's private balance.
    case send(UInt64, to: Address)
    /// Moves private SOL, in lamports, to a public address.
    case withdraw(UInt64, to: Address)
    /// Moves private SOL, in lamports, into a new redeem code, plus the public SOL that redeeming it costs.
    case createCode(UInt64)
    /// Sweeps a redeem code's SOL into the account's private balance.
    case redeem(RedeemCode)
    /// Sweeps the account's own redeem code at an index back into its private balance.
    case takeBack(index: UInt32)
}
