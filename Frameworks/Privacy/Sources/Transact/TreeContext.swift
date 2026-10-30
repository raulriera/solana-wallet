/// The root positions that a transact proof was made against, for one input tree.
struct TreeContext: Sendable, Equatable {
    let utxoTreeRootIndex: UInt16

    let nullifierTreeRootIndex: UInt16

    /// Writes both positions as little-endian 16-bit integers.
    ///
    /// - Parameter writer: The writer that receives the context.
    func write(to writer: inout WincodeWriter) {
        writer.append(utxoTreeRootIndex)
        writer.append(nullifierTreeRootIndex)
    }
}
