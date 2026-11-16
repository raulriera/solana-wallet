import Transactions

nonisolated extension TokenAmount {
    /// Creates a SOL amount from lamports.
    ///
    /// - Parameter lamports: The amount in lamports, SOL's smallest unit.
    init(lamports: UInt64) {
        self.init(amount: lamports, decimals: Asset.nativeSOL.decimals)
    }
}
