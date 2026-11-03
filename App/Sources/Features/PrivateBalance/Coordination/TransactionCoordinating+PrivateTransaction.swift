import RPC
import Transactions

extension TransactionCoordinating {
    /// Simulates a prepared private transaction, charging a redeem or take-back's network fee to its trailing deposit.
    ///
    /// - Parameter transaction: The prepared transaction.
    /// - Returns: The simulation to approve and the transaction to complete.
    /// - Throws: A ``Redemption/FeeError`` if the fee is unknown or changes, ``PrivateBalanceError/codeUnderfunded``
    ///   if the fee exceeds the code's SOL, or a preparation, RPC, or cancellation error.
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

    /// Reads a simulation's network fee, including the service tip.
    ///
    /// - Parameter simulation: The simulation.
    /// - Returns: The network fee and the service tip, in lamports.
    /// - Throws: ``Redemption/FeeError/unknown`` without a fee.
    private static func networkFee(of simulation: Simulation) throws -> UInt64 {
        guard let fee = simulation.networkFee else { throw Redemption.FeeError.unknown }
        return fee
    }
}
