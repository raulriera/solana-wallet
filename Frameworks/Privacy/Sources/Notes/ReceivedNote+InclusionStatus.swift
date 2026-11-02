import ModularArithmetic
import RPC
import Transactions

extension ReceivedNote {
    /// Whether a note's UTXO is in its tree under a root that the tree's account holds on chain.
    enum InclusionStatus: Sendable, Equatable {
        /// The proof leads the note's UTXO hash at its leaf index to the root that the tree's account holds at the
        /// proof's root index.
        case included
        /// The proof leads to its root, but the account that was read doesn't hold that root at the proof's root
        /// index, as when the indexer is ahead of the read.
        case unconfirmed
        /// The proof is of another leaf or leaf index, or its path doesn't lead to its root.
        case refuted
    }

    /// Checks each note against its tree's on-chain roots, reading the notes' Merkle proofs before the trees'
    /// accounts.
    ///
    /// - Parameters:
    ///   - notes: The received notes.
    ///   - rpc: The client of the notes' network, which reads every tree's account with one request.
    ///   - indexer: The indexer of the notes' network, which reads each tree's proofs.
    /// - Returns: Each note's status, in note order.
    /// - Throws: A ``Transactions/ValidationError`` if a tree's derivation fails, a proof read's error,
    ///   ``RPC/RPCError/InvalidResponse/mismatchedProofs`` if the indexer doesn't return one proof per note, an RPC
    ///   error, ``RPC/GetMultipleAccountsError/invalidAddressCount`` for notes of more than 100 trees, a
    ///   ``ShieldedPool/TreeError`` for an account that isn't a valid tree, or `CancellationError`.
    @concurrent
    static func inclusionStatuses(
        of notes: [ReceivedNote],
        rpc: some RPC,
        indexer: some PrivateNoteProviding
    ) async throws -> [InclusionStatus] {
        let treeIDs = Set(notes.map(\.treeID)).sorted()
        guard !treeIDs.isEmpty else { return [] }
        let trees = try treeIDs.map(ShieldedPool.tree(id:))
        let leaves = notes.map(\.utxo.hash)
        let positions = treeIDs.map { treeID in notes.indices.filter { notes[$0].treeID == treeID } }
        let proofs = try await withThrowingTaskGroup(of: (Int, [MerkleProof]).self) { group in
            for (index, tree) in trees.enumerated() {
                let address = tree.value
                let treeLeaves = positions[index].map { leaves[$0].bigEndianBytes }
                group.addTask { (index, try await indexer.merkleProofs(for: treeLeaves, inTree: address)) }
            }
            var proofs = [[MerkleProof]](repeating: [], count: trees.count)
            for try await (index, treeProofs) in group { proofs[index] = treeProofs }
            return proofs
        }
        guard zip(proofs, positions).allSatisfy({ $0.count == $1.count }) else {
            throw RPCError.invalidResponse(.mismatchedProofs)
        }
        let accounts = try await ShieldedPool.treeAccountData(at: trees, using: rpc)
        var statuses: [(position: Int, status: InclusionStatus)] = []
        for (index, data) in accounts.enumerated() {
            let history = try UTXORootHistory(accountData: data)
            statuses += zip(positions[index], proofs[index]).map { position, proof in
                (position, history.inclusionStatus(of: leaves[position], at: notes[position].leafIndex, provenBy: proof))
            }
        }
        return statuses.sorted { $0.position < $1.position }.map(\.status)
    }
}
