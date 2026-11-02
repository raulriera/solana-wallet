/// A provider that reads shielded transactions.
public protocol PrivateNoteProviding: Sendable {
    /// Reads the transactions with an output for any of the view tags, after a position.
    ///
    /// - Parameters:
    ///   - tags: The 32-byte view tags.
    ///   - position: The position from an earlier read of the same tags, or `nil` to read from the start.
    /// - Returns: The transactions in slot and signature order, the tree for new outputs, and the next read's position.
    /// - Throws: ``PrivateNoteError`` for an invalid tag or position, or a request, transport, response, or
    ///   cancellation error.
    func shieldedTransactions(taggedWith tags: [[UInt8]], after position: NoteSyncPosition?) async throws
        -> ShieldedTransactionBatch

    /// Reads the transactions that spent any of the nullifiers.
    ///
    /// - Parameter nullifiers: The 32-byte nullifiers.
    /// - Returns: Each spending transaction once, in slot and signature order.
    /// - Throws: ``PrivateNoteError/invalidNullifier`` for a nullifier that isn't 32 bytes, or a request,
    ///   transport, response, or cancellation error.
    func shieldedTransactions(spending nullifiers: [[UInt8]]) async throws -> [ShieldedTransaction]

    /// Whether the provider reads private notes on its network.
    var readsPrivateNotes: Bool { get async throws }
}

public extension PrivateNoteProviding {
    var readsPrivateNotes: Bool { true }
}
