import RPC

nonisolated extension Simulation {
    /// What the payer pays the network and any service besides the instructions: the network fee and every service
    /// tip, in lamports.
    ///
    /// `nil` when the fee is unknown, or when the total exceeds a 64-bit integer.
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
