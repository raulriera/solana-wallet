/// The Groth16 proof of a transact: 192 bytes that the shielded-pool program verifies.
///
/// `a` and `c` are compressed G1 points of 32 bytes each, and `b` is a G2 point of 128 big-endian
/// bytes, as the prover returns them.
struct TransactProof: Sendable, Equatable {
    /// Bytes that aren't a proof.
    enum ValidationError: Error, Equatable {
        /// A part doesn't have its length: 32 bytes for `a` and `c`, or 128 for `b`.
        case invalidLength
    }

    /// The compressed G1 point `a`.
    let a: [UInt8]

    /// The G2 point `b`.
    let b: [UInt8]

    /// The compressed G1 point `c`.
    let c: [UInt8]

    /// Creates a proof from its three points.
    ///
    /// - Parameters:
    ///   - a: The 32-byte compressed G1 point `a`.
    ///   - b: The 128-byte G2 point `b`.
    ///   - c: The 32-byte compressed G1 point `c`.
    /// - Throws: ``ValidationError/invalidLength`` if a point has another length.
    init(a: [UInt8], b: [UInt8], c: [UInt8]) throws {
        guard a.count == 32, b.count == 128, c.count == 32 else { throw ValidationError.invalidLength }
        self.a = a
        self.b = b
        self.c = c
    }

    /// Writes the proof: `a`, `b`, and `c`, without lengths.
    ///
    /// - Parameter writer: The writer that receives the proof.
    func write(to writer: inout WincodeWriter) {
        writer.append(array: a)
        writer.append(array: b)
        writer.append(array: c)
    }
}
