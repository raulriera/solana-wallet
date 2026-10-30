import ModularArithmetic
import RPC

extension TransactPlan {
    /// One declared input tree's proofs for a transact, checked against each other.
    struct TreeWitness: Sendable {
        private static let utxoRootHistoryCapacity: UInt16 = 500

        private static let nullifierRootHistoryCapacity: UInt16 = 100

        let slot: PublicInputs.TreeSlot

        let context: TreeContext

        /// The inclusion proofs of the tree's spent UTXOs, in input slot order.
        let inclusionProofs: [MerkleProof]

        /// The non-inclusion proofs of the tree's input slots' nullifiers, padding included, in input slot order.
        let nonInclusionProofs: [NonInclusionProof]

        /// Creates a witness by checking a tree's proofs and taking its roots from them.
        ///
        /// - Parameters:
        ///   - treeID: The tree's ID.
        ///   - inclusionProofs: The inclusion proofs of one read, at least one.
        ///   - nonInclusionProofs: The non-inclusion proofs of one read, at least one.
        /// - Throws: ``ValidationError/inconsistentProofs`` if a read is empty or its proofs disagree on their root
        ///   or its position, ``ValidationError/rootIndexOutOfRange`` for a position beyond 500 UTXO roots or 100
        ///   nullifier roots, ``ValidationError/invalidRoot`` for a root at or above r, or
        ///   ``ValidationError/invalidNonInclusionProof`` unless each low element is below its nullifier and each
        ///   high element above it.
        init(treeID: UInt16, inclusionProofs: [MerkleProof], nonInclusionProofs: [NonInclusionProof]) throws {
            guard let inclusion = inclusionProofs.first, let nonInclusion = nonInclusionProofs.first,
                  inclusionProofs.allSatisfy({ $0.root == inclusion.root && $0.rootIndex == inclusion.rootIndex }),
                  nonInclusionProofs.allSatisfy({ $0.root == nonInclusion.root && $0.rootIndex == nonInclusion.rootIndex })
            else { throw ValidationError.inconsistentProofs }
            guard inclusion.rootIndex < Self.utxoRootHistoryCapacity,
                  nonInclusion.rootIndex < Self.nullifierRootHistoryCapacity else { throw ValidationError.rootIndexOutOfRange }
            guard let utxoRoot = Poseidon.Element(bigEndianBytes: inclusion.root),
                  let nullifierRoot = Poseidon.Element(bigEndianBytes: nonInclusion.root) else { throw ValidationError.invalidRoot }
            guard nonInclusionProofs.allSatisfy({
                $0.lowElement.lexicographicallyPrecedes($0.nullifier) && $0.nullifier.lexicographicallyPrecedes($0.highElement)
            }) else { throw ValidationError.invalidNonInclusionProof }
            slot = PublicInputs.TreeSlot(treeID: treeID, utxoRoot: utxoRoot, nullifierRoot: nullifierRoot)
            context = TreeContext(utxoTreeRootIndex: inclusion.rootIndex, nullifierTreeRootIndex: nonInclusion.rootIndex)
            self.inclusionProofs = inclusionProofs
            self.nonInclusionProofs = nonInclusionProofs
        }
    }
}
