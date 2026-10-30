import RPC

nonisolated extension Simulation {
    /// The network fee plus every service tip, in lamports, or `nil` if unknown or larger than `UInt64.max`.
    var networkFee: UInt64? {
        guard let fee else { return nil }
        var total = fee
        for tip in tips {
            let (sum, overflow) = total.addingReportingOverflow(tip.tipLamports)
            guard !overflow else { return nil }
            total = sum
        }
        return total
    }
}
