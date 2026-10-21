/// A provider that indexes Solana Rings' shielded transactions and the proofs of their trees.
///
/// Reads by view tag return only the default ring's confidential transactions. Reads by nullifier return
/// every spend, whatever its ring. Proof reads return the Merkle data that a transfer proof needs. Requests
/// are single-attempt and read every page; an empty input sends no request.
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

    /// Reads the inclusion proofs of UTXO hashes in one tree, from one consistent view of it.
    ///
    /// - Parameters:
    ///   - leaves: At most 1,000 32-byte UTXO hashes.
    ///   - tree: The tree account's base-58 address.
    /// - Returns: One proof per leaf, in order, for that leaf and tree.
    /// - Throws: ``PrivateNoteError`` for an invalid leaf or tree or too many leaves, or a request, transport,
    ///   response, or cancellation error, such as a server error for a leaf that the indexer doesn't hold yet.
    func merkleProofs(for leaves: [[UInt8]], inTree tree: String) async throws -> [MerkleProof]

    /// Reads the non-inclusion proofs of nullifiers in one tree, from one consistent view of it.
    ///
    /// - Parameters:
    ///   - nullifiers: At most 1,000 32-byte nullifiers.
    ///   - tree: The tree account's base-58 address.
    /// - Returns: One proof per nullifier, in order, for that nullifier and tree.
    /// - Throws: ``PrivateNoteError`` for an invalid nullifier or tree or too many nullifiers, or a request,
    ///   transport, response, or cancellation error, such as a server error for a nullifier that is already used.
    func nonInclusionProofs(for nullifiers: [[UInt8]], inTree tree: String) async throws -> [NonInclusionProof]

    /// Whether the provider reads private notes and proves private transfers now, without sending a request.
    ///
    /// A provider that forwards to another, such as one that follows a saved choice, answers for the provider
    /// that receives its next request. The default is `true`.
    /// - Throws: An error that keeps the provider from answering, such as a missing key or a cancellation.
    var readsPrivateNotes: Bool { get async throws }
}

public extension PrivateNoteProviding {
    /// Answers that the provider reads private notes and proves private transfers.
    var readsPrivateNotes: Bool { true }
}
