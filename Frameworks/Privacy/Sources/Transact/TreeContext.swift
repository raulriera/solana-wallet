/// The root positions that a transact proof was made against, for one input tree.
///
/// The indexer reports each position with the inclusion and non-inclusion proofs. A transact
/// declares one context per input tree, in the order that it declares the trees.
struct TreeContext: Sendable, Equatable {
    /// The position of the UTXO tree's root in its root history.
    let utxoTreeRootIndex: UInt16

    /// The position of the nullifier tree's root in its root history.
    let nullifierTreeRootIndex: UInt16

    /// Writes the context: both positions as little-endian 16-bit integers.
    ///
    /// - Parameter writer: The writer that receives the context.
    func write(to writer: inout WincodeWriter) {
        writer.append(utxoTreeRootIndex)
        writer.append(nullifierTreeRootIndex)
    }
}
