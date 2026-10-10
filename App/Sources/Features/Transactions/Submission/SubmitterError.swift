/// A submission prerequisite or acknowledgment that cannot be accepted.
nonisolated enum SubmitterError: Error, Sendable, Equatable {
    /// At least one required signature slot is still empty.
    case missingSignatures
    /// The signed message or preserved signatures differ from the reviewed transaction.
    case transactionMismatch
    /// The provider acknowledged another signature; the local transaction may still have been received.
    case responseMismatch(expectedSignature: String)
    /// No supplied RPC serves the transaction's network.
    case noProviders
}
