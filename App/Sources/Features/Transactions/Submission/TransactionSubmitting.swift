/// A type that submits a reviewed, signed transaction.
nonisolated protocol TransactionSubmitting: Sendable {
    /// Checks a signed transaction, then submits it through every supplied RPC at once.
    ///
    /// - Parameter signed: The signed transaction.
    /// - Returns: The transaction's receipt.
    /// - Throws: A missing-signature error, or a ``DeliveryError`` with the receipt.
    func submit(_ signed: SignedTransaction) async throws -> Submission
}
