/// A provider that reads shielded transactions and the Merkle proofs of their trees.
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

    /// Reads the inclusion proofs of UTXO hashes in one tree, from one consistent view of it.
    ///
    /// - Parameters:
    ///   - leaves: At most 1,000 32-byte UTXO hashes.
    ///   - tree: The tree account's base-58 address.
    /// - Returns: One proof per leaf, in order.
    /// - Throws: ``PrivateNoteError`` for an invalid leaf or tree or too many leaves, or a request, transport,
    ///   response, or cancellation error.
    func merkleProofs(for leaves: [[UInt8]], inTree tree: String) async throws -> [MerkleProof]

    /// Reads the non-inclusion proofs of nullifiers in one tree, from one consistent view of it.
    ///
    /// - Parameters:
    ///   - nullifiers: At most 1,000 32-byte nullifiers.
    ///   - tree: The tree account's base-58 address.
    /// - Returns: One proof per nullifier, in order.
    /// - Throws: ``PrivateNoteError`` for an invalid nullifier or tree or too many nullifiers, or a request,
    ///   transport, response, or cancellation error.
    func nonInclusionProofs(for nullifiers: [[UInt8]], inTree tree: String) async throws -> [NonInclusionProof]

    /// Whether the provider reads private notes and proves private transfers.
    var readsPrivateNotes: Bool { get async throws }
}

public extension PrivateNoteProviding {
    var readsPrivateNotes: Bool { true }
}
