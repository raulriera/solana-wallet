import Transactions

/// A private-balance transaction that a person asks for.
nonisolated enum PrivateTransactionRequest: Equatable, Sendable {
    /// Moves an amount of a public asset, in its smallest unit, into the account's private balance.
    case deposit(UInt64, of: PrivateAsset = .sol)
    /// Sends private SOL, in lamports, to another account's private balance.
    case send(UInt64, to: Address)
    /// Moves an amount of a private asset, in its smallest unit, to an owner's public balance.
    case withdraw(UInt64, of: PrivateAsset = .sol, to: Address)
    /// Moves private SOL, in lamports, into a new redeem code, plus the public SOL that redeeming it costs.
    case createCode(UInt64)
    /// Sweeps a redeem code's SOL into the account's private balance.
    case redeem(RedeemCode)
    /// Sweeps the account's own redeem code at an index back into its private balance.
    case takeBack(index: UInt32)
}
