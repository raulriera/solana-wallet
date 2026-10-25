import Portfolio

nonisolated extension Amount {
    /// SOL counted in lamports, SOL's smallest unit.
    /// - Parameter lamports: The lamports.
    init(lamports: UInt64) {
        self.init(units: lamports, decimals: 9)
    }
}
