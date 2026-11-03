/// A provider that reads shielded transactions and the Merkle proofs of their outputs.
public protocol PrivateNoteProviding: Sendable {
    /// Reads one batch of the transactions with an output for any of the view tags, after a position.
    ///
    /// - Parameters:
    ///   - tags: The 32-byte view tags.
    ///   - position: The position from an earlier read of the same tags, or `nil` to read from the start.
    /// - Returns: The transactions in slot and signature order, the tree for new outputs, the next read's position,
    ///   and whether more transactions come after it.
    /// - Throws: ``PrivateNoteError`` for an invalid tag or position, or a request, transport, response, or
    ///   cancellation error.
    func shieldedTransactions(taggedWith tags: [[UInt8]], after position: NoteSyncPosition?) async throws
        -> ShieldedTransactionBatch

    /// Reads the transactions that spent any of the nullifiers, up to the provider's limit for one read.
    ///
    /// - Parameter nullifiers: The 32-byte nullifiers.
    /// - Returns: Each spending transaction that the read reached once, in slot and signature order.
    /// - Throws: ``PrivateNoteError/invalidNullifier`` for a nullifier that isn't 32 bytes, or a request,
    ///   transport, response, or cancellation error.
    func shieldedTransactions(spending nullifiers: [[UInt8]]) async throws -> [ShieldedTransaction]

    /// Reads the inclusion proofs of UTXO hashes in one tree.
    ///
    /// - Parameters:
    ///   - leaves: The 32-byte UTXO hashes.
    ///   - tree: The tree account's base-58 address.
    /// - Returns: The proofs that the provider returned for the leaves, in request order.
    /// - Throws: ``PrivateNoteError/invalidLeaf`` or ``PrivateNoteError/invalidTree`` for an invalid leaf or tree, or a
    ///   request, transport, response, or cancellation error.
    func merkleProofs(for leaves: [[UInt8]], inTree tree: String) async throws -> [MerkleProof]
}
