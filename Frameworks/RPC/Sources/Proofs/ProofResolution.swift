/// The roots that a prover read from its indexer and proved a transfer against.
public struct ProofResolution: Sendable, Equatable {
    /// A requested tree and the roots of its inputs' proofs.
    public struct Tree: Sendable, Equatable {
        public let id: UInt16
        /// The tree account's 32-byte address.
        public let address: [UInt8]
        /// The 32-byte UTXO tree root.
        public let utxoRoot: [UInt8]
        /// The 32-byte nullifier tree root.
        public let nullifierRoot: [UInt8]
        /// The UTXO root's position in the tree's root history.
        public let utxoRootIndex: UInt16
        /// The nullifier root's position in the tree's root history.
        public let nullifierRootIndex: UInt16
    }

    /// The requested trees, in request order.
    public let trees: [Tree]
    /// The 32-byte public input hash of the statement with the resolved tree slots.
    public let publicInputHash: [UInt8]
}

/// A transfer's Groth16 proof and the roots that the prover proved it against.
public struct IndexedTransferProof: Sendable, Equatable {
    public let proof: TransferProof
    public let resolution: ProofResolution
}
