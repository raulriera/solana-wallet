import Portfolio

nonisolated extension Amount {
    /// Creates a SOL amount from lamports.
    ///
    /// - Parameter lamports: The amount in lamports, SOL's smallest unit.
    init(lamports: UInt64) {
        self.init(units: lamports, decimals: 9)
    }
}
