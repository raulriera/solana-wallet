/// A provider that indexes Solana Rings' shielded transactions.
///
/// Reads by view tag return only the default ring's confidential transactions. Reads by nullifier return
/// every spend, whatever its ring. Requests are single-attempt and read every page; an empty input sends
/// no request.
public protocol PrivateNoteProviding: Sendable {
    /// Reads the transactions with an output for any of the view tags, after a position.
    ///
    /// The result holds confidential transactions and proofless deposits, which come from separate
    /// indexer streams. Each deposit is one output without a transaction viewing key or salt.
    /// - Parameters:
    ///   - tags: 32-byte view tags, such as an account's Ed25519 public key.
    ///   - position: The position from an earlier read of the same tags, or `nil` to read from the start.
    /// - Returns: The transactions in slot and signature order, the tree for new outputs, and the position
    ///   where the next read resumes.
    /// - Throws: ``PrivateNoteError`` for an invalid tag or position, or a request, transport, response, or
    ///   cancellation error.
    func shieldedTransactions(taggedWith tags: [[UInt8]], after position: NoteSyncPosition?) async throws
        -> ShieldedTransactionBatch

    /// Reads the transactions that spent any of the nullifiers.
    ///
    /// - Parameter nullifiers: 32-byte nullifiers; a nullifier that nothing spent returns nothing.
    /// - Returns: Each spending transaction once, in slot and signature order.
    /// - Throws: ``PrivateNoteError/invalidNullifier`` for a nullifier that isn't 32 bytes, or a request,
    ///   transport, response, or cancellation error.
    func shieldedTransactions(spending nullifiers: [[UInt8]]) async throws -> [ShieldedTransaction]
}
