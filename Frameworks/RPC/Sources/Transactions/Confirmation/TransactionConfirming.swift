/// A type that waits for a sent transaction's outcome.
public protocol TransactionConfirming: Sendable {
    /// Waits until the transaction's execution is finalized, or it can never land.
    ///
    /// - Parameter pending: The transaction's pending outcome.
    /// - Returns: The succeeded, failed, or dropped outcome.
    /// - Throws: A network, response, RPC, or cancellation error.
    func confirm(_ pending: TransactionOutcome) async throws -> TransactionOutcome
}
