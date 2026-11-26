import Transactions

/// A type that waits for a sent transaction's outcome.
nonisolated protocol TransactionConfirming: Sendable {
    /// Waits until the transaction's execution is finalized, or it can never land.
    ///
    /// - Parameters:
    ///   - pending: The transaction's pending outcome.
    ///   - transaction: The sent transaction.
    /// - Returns: The succeeded, failed, or dropped outcome.
    /// - Throws: A network, response, RPC, or cancellation error.
    func confirm(_ pending: TransactionOutcome, of transaction: Transaction) async throws -> TransactionOutcome
}
