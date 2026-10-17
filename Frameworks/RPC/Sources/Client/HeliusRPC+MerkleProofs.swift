import Encoding

extension HeliusRPC {
    /// Reads the inclusion proofs of UTXO hashes in one tree with one `getMerkleProofs` request to Helius's
    /// Solana Rings indexer.
    ///
    /// The indexer reads every leaf in one database transaction, so the proofs share one root.
    /// - Parameters:
    ///   - leaves: At most 1,000 32-byte UTXO hashes.
    ///   - tree: The tree account's base-58 address.
    /// - Returns: One proof per leaf, in order.
    /// - Throws: ``PrivateNoteError/invalidLeaf``, ``PrivateNoteError/invalidTree``, or
    ///   ``PrivateNoteError/tooManyLeaves`` before sending, `RPCError.invalidResponse(.mismatchedProofs)` for
    ///   proofs of other leaves or another tree, another `RPCError`, or `CancellationError`.
    @concurrent
    public func merkleProofs(for leaves: [[UInt8]], inTree tree: String) async throws -> [MerkleProof] {
        guard leaves.allSatisfy({ $0.count == 32 }) else { throw PrivateNoteError.invalidLeaf }
        let gateway = gateway
        return try await Self.proofs(of: leaves, inTree: tree, leaf: \.leaf) { tree, leaves in
            try await gateway.send(GetMerkleProofs(treeAccount: tree, leaves: leaves), at: GetMerkleProofs.method).proofs
        }
    }

    /// Reads the non-inclusion proofs of nullifiers in one tree with one `getNonInclusionProofs` request to
    /// Helius's Solana Rings indexer.
    ///
    /// The indexer reads every nullifier in one database transaction, so the proofs share one root.
    /// - Parameters:
    ///   - nullifiers: At most 1,000 32-byte nullifiers.
    ///   - tree: The tree account's base-58 address.
    /// - Returns: One proof per nullifier, in order.
    /// - Throws: ``PrivateNoteError/invalidNullifier``, ``PrivateNoteError/invalidTree``, or
    ///   ``PrivateNoteError/tooManyLeaves`` before sending, `RPCError.invalidResponse(.mismatchedProofs)` for
    ///   proofs of other nullifiers or another tree, another `RPCError`, or `CancellationError`.
    @concurrent
    public func nonInclusionProofs(for nullifiers: [[UInt8]], inTree tree: String) async throws -> [NonInclusionProof] {
        guard nullifiers.allSatisfy({ $0.count == 32 }) else { throw PrivateNoteError.invalidNullifier }
        let gateway = gateway
        return try await Self.proofs(of: nullifiers, inTree: tree, leaf: \.nullifier) { tree, leaves in
            try await gateway.send(GetNonInclusionProofs(treeAccount: tree, leaves: leaves),
                                   at: GetNonInclusionProofs.method).proofs
        }
    }

    /// Reads one proof per leaf with one request and checks that the proofs answer it.
    ///
    /// - Parameters:
    ///   - leaves: The 32-byte leaves.
    ///   - tree: The tree account's base-58 address.
    ///   - leaf: The leaf that a proof proves.
    ///   - read: Sends the request with the tree and the base-58 leaves.
    /// - Returns: The proofs in leaf order, or none without a request for no leaves.
    /// - Throws: ``PrivateNoteError/invalidTree`` or ``PrivateNoteError/tooManyLeaves`` before sending,
    ///   `RPCError.invalidResponse(.mismatchedProofs)` unless each proof names its leaf and the tree, or an error
    ///   from `read`.
    private static func proofs<Proof: Sendable>(
        of leaves: [[UInt8]],
        inTree tree: String,
        leaf: KeyPath<Proof, [UInt8]>,
        read: (String, [String]) async throws -> [TreeProof<Proof>]
    ) async throws -> [Proof] {
        guard Base58.decode(tree, byteCount: 32) != nil else { throw PrivateNoteError.invalidTree }
        guard leaves.count <= 1_000 else { throw PrivateNoteError.tooManyLeaves }
        guard !leaves.isEmpty else { return [] }
        let proofs = try await read(tree, leaves.map(Base58.encode))
        guard proofs.map({ $0.proof[keyPath: leaf] }) == leaves, proofs.allSatisfy({ $0.tree == tree }) else {
            throw RPCError.invalidResponse(.mismatchedProofs)
        }
        return proofs.map(\.proof)
    }
}
