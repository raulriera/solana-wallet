@testable import Privacy
import Testing

/// Verifies the compression of a proof's G1 points with the generator (1, 2) and edge values, as
/// zolana's TypeScript proof tests check them. Random points are checked through whole proofs in
/// ``TransactPlanProofTests``.
struct ProofPointTests {
    /// Verifies compressed points: the generator has a small y and no flag, its negation has a
    /// large y and the flag, the point at infinity stays zero either way, and a zero y stays zero
    /// when negated.
    ///
    /// - Parameters:
    ///   - x: The x coordinate's last byte; the other bytes are zero.
    ///   - y: The y coordinate's last byte; the other bytes are zero.
    ///   - negated: Whether the point is negated.
    ///   - firstByte: The compressed point's first byte.
    @Test(arguments: [
        (1, 2, false, 0x00), (1, 2, true, 0x80), (0, 0, false, 0x00), (0, 0, true, 0x00), (5, 0, true, 0x00),
    ] as [(UInt8, UInt8, Bool, UInt8)])
    func `Points compress with the sign of y`(x: UInt8, y: UInt8, negated: Bool, firstByte: UInt8) throws {
        let compressed = try ProofPoint.compressed(x: Self.word(x), y: Self.word(y), negated: negated)

        #expect(compressed == [firstByte] + Self.word(x).dropFirst())
    }

    /// Verifies that y at `(p - 1) / 2` has no flag and one above it has the flag.
    ///
    /// - Parameters:
    ///   - y: The y coordinate.
    ///   - firstByte: The compressed point's first byte, for x = 1.
    @Test(arguments: [
        ("183227397098d014dc2822db40c0ac2ecbc0b548b438e5469e10460b6c3e7ea3", 0x00),
        ("183227397098d014dc2822db40c0ac2ecbc0b548b438e5469e10460b6c3e7ea4", 0x80),
    ] as [(String, UInt8)])
    func `The flag starts above half the modulus`(y: String, firstByte: UInt8) throws {
        #expect(try ProofPoint.compressed(x: Self.word(1), y: fixtureBytes(y))[0] == firstByte)
    }

    /// Verifies that coordinates at the modulus or of another length are rejected.
    ///
    /// - Parameters:
    ///   - x: The x coordinate.
    ///   - y: The y coordinate.
    @Test(arguments: [
        ("30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47", "0000000000000000000000000000000000000000000000000000000000000002"),
        ("0000000000000000000000000000000000000000000000000000000000000001", "30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47"),
        ("00000000000000000000000000000000000000000000000000000000000001", "0000000000000000000000000000000000000000000000000000000000000002"),
    ] as [(String, String)])
    func `Invalid coordinates are rejected`(x: String, y: String) throws {
        let (x, y) = (try fixtureBytes(x), try fixtureBytes(y))

        #expect(throws: ProofPoint.ValidationError.invalidCoordinate) {
            try ProofPoint.compressed(x: x, y: y, negated: true)
        }
    }

    /// Creates a 32-byte big-endian word whose last byte is a small value.
    ///
    /// - Parameter value: The last byte.
    /// - Returns: The word.
    private static func word(_ value: UInt8) -> [UInt8] {
        [UInt8](repeating: 0, count: 31) + [value]
    }
}
