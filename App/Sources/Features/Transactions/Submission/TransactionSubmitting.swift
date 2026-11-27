/// A type that submits a reviewed, signed transaction.
nonisolated protocol TransactionSubmitting: Sendable {
    /// Checks a signed transaction, then submits it once through its RPC.
    ///
    /// - Parameter signed: The signed transaction.
    /// - Returns: The transaction's pending outcome, whether or not the RPC accepted it.
    /// - Throws: A missing-signature error.
    func submit(_ signed: SignedTransaction) async throws -> TransactionOutcome
}
