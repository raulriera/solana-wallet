/// How a sent transaction settled.
nonisolated enum TransactionOutcome: Equatable, Sendable {
    case succeeded
    /// The transaction landed and failed.
    case failed
    /// The transaction can never land.
    case dropped
}
