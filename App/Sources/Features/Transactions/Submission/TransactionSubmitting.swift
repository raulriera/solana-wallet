/// A type that submits a reviewed, signed transaction.
nonisolated protocol TransactionSubmitting: Sendable {
    /// Checks a signed transaction, then submits it once through its RPC.
    ///
    /// - Parameter signed: The signed transaction.
    /// - Returns: The transaction's pending outcome.
    /// - Throws: A missing-signature error, or a ``DeliveryError`` with the pending outcome.
    func submit(_ signed: SignedTransaction) async throws -> TransactionOutcome
}
