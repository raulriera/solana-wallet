/// A type that submits a reviewed, signed transaction without rebuilding or resigning it.
nonisolated protocol TransactionSubmitting: Sendable {
    /// Submits concurrently through all supplied RPCs after checking transaction prerequisites.
    ///
    /// - Parameter signed: The approved transaction returned by the signing workflow.
    /// - Returns: A plain receipt after the attempts finish and at least one RPC acknowledges it.
    /// - Throws: A missing-signature error, or a ``DeliveryError`` that retains the receipt. A failure after dispatch
    ///   doesn't prove the transaction wasn't received; use the receipt's signature for subsequent status checks.
    func submit(_ signed: SignedTransaction) async throws -> Submission
}
