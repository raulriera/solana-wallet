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

        /// Creates a resolved tree.
        ///
        /// - Parameters:
        ///   - id: The tree's ID.
        ///   - address: The tree account's 32-byte address.
        ///   - utxoRoot: The 32-byte UTXO tree root.
        ///   - nullifierRoot: The 32-byte nullifier tree root.
        ///   - utxoRootIndex: The UTXO root's position in the root history.
        ///   - nullifierRootIndex: The nullifier root's position in the root history.
        public init(id: UInt16, address: [UInt8], utxoRoot: [UInt8], nullifierRoot: [UInt8], utxoRootIndex: UInt16,
                    nullifierRootIndex: UInt16) {
            self.id = id
            self.address = address
            self.utxoRoot = utxoRoot
            self.nullifierRoot = nullifierRoot
            self.utxoRootIndex = utxoRootIndex
            self.nullifierRootIndex = nullifierRootIndex
        }
    }

    /// The requested trees, in request order.
    public let trees: [Tree]
    /// The 32-byte public input hash of the statement with the resolved tree slots.
    public let publicInputHash: [UInt8]

    /// Creates a resolution.
    ///
    /// - Parameters:
    ///   - trees: The resolved trees in request order.
    ///   - publicInputHash: The 32-byte public input hash.
    public init(trees: [Tree], publicInputHash: [UInt8]) {
        self.trees = trees
        self.publicInputHash = publicInputHash
    }
}

/// A transfer's Groth16 proof and the roots that the prover proved it against.
public struct IndexedTransferProof: Sendable, Equatable {
    public let proof: TransferProof
    public let resolution: ProofResolution

    /// Creates an indexed proof.
    ///
    /// - Parameters:
    ///   - proof: The proof and the proving key's digest.
    ///   - resolution: The resolved trees and public input hash.
    public init(proof: TransferProof, resolution: ProofResolution) {
        self.proof = proof
        self.resolution = resolution
    }
}
