/// A transfer's Groth16 proof as the prover returns it, with the roots that the prover resolved.
///
/// Coordinates are 32 big-endian bytes, as received: `a` isn't negated, and no point is compressed or
/// checked against the curve. The caller checks the proving key's digest and the resolution, and converts
/// the points for the shielded-pool program.
public struct TransferProof: Sendable, Equatable {
    /// A G1 point's affine coordinates.
    public struct G1Point: Sendable, Equatable {
        /// The 32-byte big-endian x-coordinate.
        public let x: [UInt8]
        /// The 32-byte big-endian y-coordinate.
        public let y: [UInt8]

        /// Creates a point from its coordinates.
        ///
        /// - Parameters:
        ///   - x: The 32-byte big-endian x-coordinate.
        ///   - y: The 32-byte big-endian y-coordinate.
        public init(x: [UInt8], y: [UInt8]) {
            self.x = x
            self.y = y
        }
    }

    /// The roots that the prover read for one input tree.
    public struct ResolvedTree: Sendable, Equatable {
        /// The tree account's base-58 address.
        public let address: String
        /// The tree's ID.
        public let id: UInt16
        /// The 32-byte UTXO tree root.
        public let utxoRoot: [UInt8]
        /// The 32-byte nullifier tree root.
        public let nullifierRoot: [UInt8]
        /// The UTXO root's position in its root history.
        public let utxoRootIndex: UInt16
        /// The nullifier root's position in its root history.
        public let nullifierRootIndex: UInt16

        /// Creates a resolved tree.
        ///
        /// - Parameters:
        ///   - address: The tree account's base-58 address.
        ///   - id: The tree's ID.
        ///   - utxoRoot: The 32-byte UTXO tree root.
        ///   - nullifierRoot: The 32-byte nullifier tree root.
        ///   - utxoRootIndex: The UTXO root's position.
        ///   - nullifierRootIndex: The nullifier root's position.
        public init(address: String, id: UInt16, utxoRoot: [UInt8], nullifierRoot: [UInt8], utxoRootIndex: UInt16,
                    nullifierRootIndex: UInt16) {
            self.address = address
            self.id = id
            self.utxoRoot = utxoRoot
            self.nullifierRoot = nullifierRoot
            self.utxoRootIndex = utxoRootIndex
            self.nullifierRootIndex = nullifierRootIndex
        }
    }

    /// The prover's account of the statement that it proved.
    public struct Resolution: Sendable, Equatable {
        /// The input trees, in the order that the request listed them.
        public let trees: [ResolvedTree]
        /// The 32-byte public input hash, with the resolved tree slots.
        public let publicInputHash: [UInt8]

        /// Creates a resolution.
        ///
        /// - Parameters:
        ///   - trees: The resolved input trees.
        ///   - publicInputHash: The 32-byte public input hash.
        public init(trees: [ResolvedTree], publicInputHash: [UInt8]) {
            self.trees = trees
            self.publicInputHash = publicInputHash
        }
    }

    /// The proof's point `a`, not negated.
    public let a: G1Point
    /// The proof's G2 point `b`: 128 bytes of four 32-byte words, as the prover returns them.
    public let b: [UInt8]
    /// The proof's point `c`.
    public let c: G1Point
    /// The SHA-256 digest of the proving key that the prover used.
    public let provingKeyDigest: [UInt8]
    /// The roots and public input hash that the prover resolved.
    public let resolution: Resolution

    /// Creates a proof.
    ///
    /// - Parameters:
    ///   - a: The point `a`, not negated.
    ///   - b: The 128-byte point `b`.
    ///   - c: The point `c`.
    ///   - provingKeyDigest: The proving key's 32-byte SHA-256 digest.
    ///   - resolution: The resolved roots and public input hash.
    public init(a: G1Point, b: [UInt8], c: G1Point, provingKeyDigest: [UInt8], resolution: Resolution) {
        self.a = a
        self.b = b
        self.c = c
        self.provingKeyDigest = provingKeyDigest
        self.resolution = resolution
    }
}
