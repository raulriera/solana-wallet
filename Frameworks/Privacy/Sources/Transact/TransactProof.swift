/// The 192-byte Groth16 proof of a transact.
struct TransactProof: Sendable, Equatable {
    /// Bytes that aren't a proof.
    enum ValidationError: Error, Equatable {
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

    /// Writes `a`, `b`, and `c` without lengths.
    ///
    /// - Parameter writer: The writer that receives the proof.
    func write(to writer: inout WincodeWriter) {
        writer.append(array: a)
        writer.append(array: b)
        writer.append(array: c)
    }
}
