/// A type that submits a reviewed, signed transaction without rebuilding or resigning it.
nonisolated protocol TransactionSubmitting: Sendable {
    /// Submits once after verifying signatures, review consistency, fee, and lifetime.
    ///
    /// - Parameter signed: The approved transaction returned by the signing workflow.
    /// - Returns: A receipt identifying the transaction accepted by the selected provider.
    /// - Throws: A validation, RPC, or cancellation error. A failure after dispatch doesn't
    ///   prove the transaction wasn't received; use its signature for subsequent status checks.
    func submit(_ signed: SignedTransaction) async throws -> Submission
}
