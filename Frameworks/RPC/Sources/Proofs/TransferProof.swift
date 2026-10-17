/// A transfer's Groth16 proof as the prover returns it.
///
/// Coordinates are 32 big-endian bytes, as received: `a` isn't negated, and no point is compressed or
/// checked against the curve. The caller checks the proving key's digest and converts the points for the
/// shielded-pool program.
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

    /// The proof's point `a`, not negated.
    public let a: G1Point
    /// The proof's G2 point `b`: 128 bytes of four 32-byte words, as the prover returns them.
    public let b: [UInt8]
    /// The proof's point `c`.
    public let c: G1Point
    /// The SHA-256 digest of the proving key that the prover used.
    public let provingKeyDigest: [UInt8]

    /// Creates a proof.
    ///
    /// - Parameters:
    ///   - a: The point `a`, not negated.
    ///   - b: The 128-byte point `b`.
    ///   - c: The point `c`.
    ///   - provingKeyDigest: The proving key's 32-byte SHA-256 digest.
    public init(a: G1Point, b: [UInt8], c: G1Point, provingKeyDigest: [UInt8]) {
        self.a = a
        self.b = b
        self.c = c
        self.provingKeyDigest = provingKeyDigest
    }
}
