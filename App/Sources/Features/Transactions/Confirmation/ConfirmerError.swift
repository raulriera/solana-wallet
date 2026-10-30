/// An error that leaves a sent transaction's outcome unknown.
nonisolated enum ConfirmerError: Error, Sendable, Equatable {
    /// The provider serves a different network than the submission.
    case networkMismatch
    case invalidResponse
}
