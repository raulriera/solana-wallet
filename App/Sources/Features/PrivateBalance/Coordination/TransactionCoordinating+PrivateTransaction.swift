import RPC
import Transactions

extension TransactionCoordinating {
    /// Simulates a prepared private transaction with its authorities, first charging a redeem or take-back's network
    /// fee to its trailing deposit.
    ///
    /// Other transactions run one simulation. A redeem or take-back runs two: the first, with no fee charged, only
    /// reads the network fee and the service tips, which the payer pays for every signature and tip; the second
    /// simulates the transaction charged with them, whose one-time account ends at zero lamports. Only the second goes
    /// to approval, and only the returned transaction completes.
    /// - Parameter transaction: A transaction from ``PrivateBalancing/prepare(_:from:on:)``.
    /// - Returns: The review to approve and the transaction to complete once it settles.
    /// - Throws: ``Redemption/FeeError/unknown`` if the provider doesn't report the fee,
    ///   ``Redemption/FeeError/changed`` if the charged transaction's fee differs,
    ///   ``PrivateBalanceError/codeUnderfunded`` if the fee exceeds the SOL left for it, or a preparation, RPC, or
    ///   cancellation error.
    func simulate(_ transaction: PreparedPrivateTransaction) async throws
        -> (simulation: Simulation, transaction: PreparedPrivateTransaction) {
        guard case .redeem = transaction.effect else {
            return (try await simulate(transaction.instructions, using: transaction.authorities), transaction)
        }
        let unpaid = try transaction.withNetworkFee(0)
        let estimate = try await simulate(unpaid.instructions, using: unpaid.authorities)
        let fee = try Self.networkFee(of: estimate)
        let charged = try transaction.withNetworkFee(fee)
        let simulation = try await simulate(charged.instructions, using: charged.authorities)
        guard try Self.networkFee(of: simulation) == fee else { throw Redemption.FeeError.changed }
        return (simulation, charged)
    }

    /// Adds a review's network fee and its service tips.
    /// - Parameter simulation: The review.
    /// - Returns: The lamports that the payer pays besides the instructions.
    /// - Throws: ``Redemption/FeeError/unknown`` without a fee, or ``Transactions/ValidationError/invalidAmount`` if
    ///   the total exceeds a 64-bit integer.
    private static func networkFee(of simulation: Simulation) throws -> UInt64 {
        guard let fee = simulation.fee else { throw Redemption.FeeError.unknown }
        return try simulation.tips.reduce(fee) { total, tip in
            let (sum, overflow) = total.addingReportingOverflow(tip.tipLamports)
            guard !overflow else { throw Transactions.ValidationError.invalidAmount }
            return sum
        }
    }
}
