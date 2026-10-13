/// A type that observes a sent transaction's execution without signing or sending it again.
nonisolated protocol TransactionConfirming: Sendable {
    /// Waits for the submitted transaction to reach confirmed or finalized commitment.
    ///
    /// - Parameter submission: The accepted signature and its original network.
    /// - Returns: The observed execution outcome and confirmation level.
    /// - Throws: A network, response, RPC, timeout, or cancellation error. A conformer may wrap it
    ///   in a ``DeliveryError`` that retains the receipt. Timeout and cancellation don't establish
    ///   transaction failure or revoke submission.
    func confirm(_ submission: Submission) async throws -> Confirmation
}
