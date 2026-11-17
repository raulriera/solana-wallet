import Privacy

nonisolated extension PrivateAsset {
    /// Returns the public lamports that a move of an amount of the asset pays into or takes out of the pool.
    ///
    /// - Parameter amount: The moved amount, in the asset's smallest unit.
    /// - Returns: The amount for SOL, or zero for a token, which moves no lamports.
    func lamports(moving amount: UInt64) -> UInt64 {
        self == .nativeSOL ? amount : 0
    }

    /// Returns the available and pending amounts of the asset in an account's notes.
    ///
    /// - Parameter state: The account's notes.
    /// - Returns: The amounts, in the asset's smallest unit.
    func balance(in state: NoteSyncState) -> PrivateBalanceStatus.Balance {
        PrivateBalanceStatus.Balance(available: state.spendableAmount(of: self), pending: state.pendingAmount(of: self))
    }
}
