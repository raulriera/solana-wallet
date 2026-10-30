/// How a sent transaction settled.
nonisolated enum TransactionOutcome: Equatable, Sendable {
    case succeeded
    /// The transaction landed and failed.
    case failed
    /// The transaction can never land.
    case dropped

    /// Creates the outcome of a record's status, or `nil` while the transaction is pending.
    ///
    /// - Parameter status: The record's status.
    init?(_ status: TransactionRecord.Status) {
        switch status {
        case .pending: return nil
        case .succeeded: self = .succeeded
        case .failed: self = .failed
        case .dropped: self = .dropped
        }
    }
}
