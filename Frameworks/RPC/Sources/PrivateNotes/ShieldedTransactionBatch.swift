/// The shielded transactions found for a set of view tags, and where the next read resumes.
public struct ShieldedTransactionBatch: Sendable, Equatable {
    /// The transactions in slot and signature order.
    public let transactions: [ShieldedTransaction]
    /// The ID of the newest tree that isn't paused, or `nil` when the indexer reports none.
    public let outputTreeID: UInt16?
    /// The position to pass to the next read of the same view tags.
    public let position: NoteSyncPosition

    /// Creates a batch.
    ///
    /// - Parameters:
    ///   - transactions: The transactions in slot and signature order.
    ///   - outputTreeID: The newest tree that isn't paused, or `nil`.
    ///   - position: The position where the next read resumes.
    init(transactions: [ShieldedTransaction], outputTreeID: UInt16?, position: NoteSyncPosition) {
        self.transactions = transactions
        self.outputTreeID = outputTreeID
        self.position = position
    }
}
