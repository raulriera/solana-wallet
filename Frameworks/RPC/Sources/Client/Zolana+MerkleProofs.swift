import Encoding

extension Zolana {
    @concurrent
    public func merkleProofs(for leaves: [[UInt8]], inTree tree: String) async throws -> [MerkleProof] {
        guard leaves.allSatisfy({ $0.count == 32 }) else { throw PrivateNoteError.invalidLeaf }
        let indexer = indexer
        return try await Self.proofs(of: leaves, inTree: tree, leaf: \.leaf) { tree, leaves in
            try await indexer.send(GetMerkleProofs(treeAccount: tree, leaves: leaves), at: GetMerkleProofs.method).proofs
        }
    }

    @concurrent
    public func nonInclusionProofs(for nullifiers: [[UInt8]], inTree tree: String) async throws -> [NonInclusionProof] {
        guard nullifiers.allSatisfy({ $0.count == 32 }) else { throw PrivateNoteError.invalidNullifier }
        let indexer = indexer
        return try await Self.proofs(of: nullifiers, inTree: tree, leaf: \.nullifier) { tree, leaves in
            try await indexer.send(GetNonInclusionProofs(treeAccount: tree, leaves: leaves),
                                   at: GetNonInclusionProofs.method).proofs
        }
    }

    /// Reads one proof per leaf with one request and checks that the proofs match the leaves and the tree.
    ///
    /// - Parameters:
    ///   - leaves: The 32-byte leaves.
    ///   - tree: The tree account's base-58 address.
    ///   - leaf: The key path to the leaf that a proof proves.
    ///   - read: The request that takes the tree and the base-58 leaves.
    /// - Returns: The proofs in leaf order.
    /// - Throws: A ``PrivateNoteError`` for invalid input, an `RPCError` for mismatched proofs, or an error from
    ///   `read`.
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
