/// A type that submits a reviewed, signed transaction without rebuilding or resigning it.
nonisolated protocol TransactionSubmitting: Sendable {
    /// Submits once per enabled provider after verifying review, signatures, fee, and lifetime.
    ///
    /// - Parameter signed: The approved transaction returned by the signing workflow.
    /// - Returns: The first acknowledgment, owning the remaining deliveries and their diagnostics.
    /// - Throws: A validation, aggregate delivery, or cancellation error. A failure after dispatch doesn't
    ///   prove the transaction wasn't received; use its signature for subsequent status checks.
    func submit(_ signed: SignedTransaction) async throws -> Submission
}
