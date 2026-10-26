/// How a sent transaction settled, as its result shows it.
nonisolated enum TransactionOutcome: Equatable, Sendable {
    /// The transaction landed without an error.
    case succeeded
    /// The transaction landed and failed; it paid its network fee and changed nothing else.
    case failed
    /// The transaction can never land, so nothing left the account.
    case dropped

    /// The outcome of a record's status.
    /// - Parameter status: The record's status.
    /// - Returns: The outcome, or `nil` while the transaction is pending.
    init?(_ status: TransactionRecord.Status) {
        switch status {
        case .pending: return nil
        case .succeeded: self = .succeeded
        case .failed: self = .failed
        case .dropped: self = .dropped
        }
    }
}
