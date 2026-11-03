/// An error that stops a transaction's submission.
nonisolated enum SubmitterError: Error, Sendable, Equatable {
    case missingSignatures
    /// The signed transaction differs from the reviewed one.
    case transactionMismatch
    /// The provider acknowledged a different signature.
    case responseMismatch(expectedSignature: String)
}
