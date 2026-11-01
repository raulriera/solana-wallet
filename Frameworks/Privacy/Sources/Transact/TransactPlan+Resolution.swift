import ModularArithmetic
import RPC

extension TransactPlan {
    private static let utxoRootHistoryCapacity: UInt16 = 500

    private static let nullifierRootHistoryCapacity: UInt16 = 100

    /// Checks the roots that the prover proved the plan against and creates the instruction's tree contexts from them.
    ///
    /// - Parameters:
    ///   - resolution: The prover's resolution of the plan's declared input trees.
    ///   - statement: The plan's ``publicInputs``.
    /// - Returns: One context per declared input tree, in declaration order.
    /// - Throws: ``ValidationError/invalidTreeContextCount`` unless the resolution has one tree per declared input
    ///   tree, ``ValidationError/invalidRoot`` for a root at or above r, ``ValidationError/rootIndexOutOfRange`` for a
    ///   position beyond 500 UTXO roots or 100 nullifier roots, or ``ValidationError/mismatchedPublicInputHash``
    ///   unless the resolution's public input hash is the statement's with the declared trees and their resolved roots.
    func treeContexts(from resolution: ProofResolution, statement: PublicInputs) throws -> [TreeContext] {
        guard resolution.trees.count == inputTreeIDs.count else { throw ValidationError.invalidTreeContextCount }
        let slots = try zip(resolution.trees, inputTreeIDs).map { tree, id in
            guard let utxoRoot = Poseidon.Element(bigEndianBytes: tree.utxoRoot),
                  let nullifierRoot = Poseidon.Element(bigEndianBytes: tree.nullifierRoot) else {
                throw ValidationError.invalidRoot
            }
            guard tree.utxoRootIndex < Self.utxoRootHistoryCapacity,
                  tree.nullifierRootIndex < Self.nullifierRootHistoryCapacity else {
                throw ValidationError.rootIndexOutOfRange
            }
            return PublicInputs.TreeSlot(treeID: id, utxoRoot: utxoRoot, nullifierRoot: nullifierRoot)
        }
        guard statement.hash(treeSlots: slots).bigEndianBytes == resolution.publicInputHash else {
            throw ValidationError.mismatchedPublicInputHash
        }
        return resolution.trees.map {
            TreeContext(utxoTreeRootIndex: $0.utxoRootIndex, nullifierTreeRootIndex: $0.nullifierRootIndex)
        }
    }
}
