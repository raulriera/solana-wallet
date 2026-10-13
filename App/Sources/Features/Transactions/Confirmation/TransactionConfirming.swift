/// A type that observes a sent transaction's execution without signing or sending it again.
nonisolated protocol TransactionConfirming: Sendable {
    /// Waits until the transaction reaches confirmed or finalized commitment, or can never land.
    ///
    /// - Parameter submission: The accepted signature, its original network, and its blockhash expiry.
    /// - Returns: The succeeded, failed, or dropped outcome and its commitment.
    /// - Throws: A network, response, RPC, or cancellation error. A conformer may wrap it in a
    ///   ``DeliveryError`` that retains the receipt. Errors and cancellation don't establish
    ///   transaction failure or revoke submission.
    func confirm(_ submission: Submission) async throws -> Confirmation
}
