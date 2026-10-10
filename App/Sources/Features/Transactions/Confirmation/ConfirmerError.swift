/// An observation failure that doesn't establish an on-chain execution outcome.
nonisolated enum ConfirmerError: Error, Sendable, Equatable {
    /// The provider serves a different network from the submission.
    case networkMismatch
    /// The response cannot describe the single requested signature consistently.
    case invalidResponse
    /// The observation deadline elapsed; the transaction's outcome remains unknown.
    case timedOut
}
