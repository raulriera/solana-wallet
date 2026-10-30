import ModularArithmetic

/// The compression of a Groth16 proof's G1 points.
enum ProofPoint {
    /// An error that rejects a point's coordinates.
    enum ValidationError: Error, Equatable {
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
    ///   - negated: Whether to negate the point first.
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
