import RPC

nonisolated extension Simulation {
    /// The network fee plus the service tip, in lamports, or `nil` if unknown or larger than `UInt64.max`.
    var networkFee: UInt64? {
        guard let fee else { return nil }
        let (total, overflow) = fee.addingReportingOverflow(requirements?.tipLamports ?? 0)
        return overflow ? nil : total
    }
}
