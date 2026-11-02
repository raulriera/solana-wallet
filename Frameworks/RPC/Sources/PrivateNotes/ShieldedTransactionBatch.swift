/// The shielded transactions found for a set of view tags, and where the next read resumes.
public struct ShieldedTransactionBatch: Sendable, Equatable {
    /// The transactions in slot and signature order.
    public let transactions: [ShieldedTransaction]
    /// The ID of the newest tree that isn't paused, or `nil` when the indexer reports none.
    public let outputTreeID: UInt16?
    /// The position to pass to the next read of the same view tags.
    public let position: NoteSyncPosition
    /// Whether the indexer holds more transactions after ``position``.
    public let moreComing: Bool
}
