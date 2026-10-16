import ModularArithmetic

/// The compression of a Groth16 proof's G1 points, as the shielded-pool program reads them.
///
/// A point's coordinates are 32-byte big-endian integers below the BN254 base field's modulus p,
/// decoded as ModularArithmetic's `BN254BaseField` elements. The compressed point is x with its top
/// bit set when y is above `(p - 1) / 2`, which holds exactly when `p - y`, the field's `-y`, is
/// below y; the point at infinity, (0, 0), compresses to 32 zero bytes. The program verifies `-A`,
/// so the prover's `A` is negated first: y becomes `-y`, and zero stays zero. Nothing here checks
/// that a point is on the curve: the program's verification rejects a proof with an invalid point,
/// and a simulation surfaces that before anything is sent.
enum ProofPoint {
    /// Coordinates that aren't a point's.
    enum ValidationError: Error, Equatable {
        /// A coordinate doesn't have 32 bytes or isn't below p.
        case invalidCoordinate
    }

    /// An element of the field that holds the coordinates.
    private typealias Coordinate = FieldElement<BN254BaseField>

    /// The flag of a compressed point whose y is above `(p - 1) / 2`.
    private static let largeYFlag: UInt8 = 0x80

    /// Compresses a G1 point, optionally negating it first.
    ///
    /// - Parameters:
    ///   - x: The 32-byte big-endian x coordinate.
    ///   - y: The 32-byte big-endian y coordinate.
    ///   - negated: Whether to compress `-point`, as the proof's `A` needs.
    /// - Returns: The 32-byte compressed point.
    /// - Throws: ``ValidationError/invalidCoordinate`` if a coordinate doesn't have 32 bytes or
    ///   isn't below p.
    static func compressed(x: [UInt8], y: [UInt8], negated: Bool = false) throws -> [UInt8] {
        guard let xCoordinate = Coordinate(bigEndianBytes: x), let yCoordinate = Coordinate(bigEndianBytes: y) else {
            throw ValidationError.invalidCoordinate
        }
        var compressed = xCoordinate.bigEndianBytes
        if xCoordinate == .zero && yCoordinate == .zero { return compressed }
        let effectiveY = negated ? -yCoordinate : yCoordinate
        if (-effectiveY).bigEndianBytes.lexicographicallyPrecedes(effectiveY.bigEndianBytes) {
            compressed[0] |= largeYFlag
        }
        return compressed
    }
}
