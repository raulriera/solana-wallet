/// A type that waits for a sent transaction's outcome.
nonisolated protocol TransactionConfirming: Sendable {
    /// Waits until the transaction's execution is finalized, or it can never land.
    ///
    /// - Parameter submission: The sent transaction's receipt.
    /// - Returns: The succeeded, failed, or dropped outcome.
    /// - Throws: A network, response, RPC, or cancellation error.
    func confirm(_ submission: Submission) async throws -> Confirmation
}
