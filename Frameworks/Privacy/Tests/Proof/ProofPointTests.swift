import Testing
@testable import Privacy

struct ProofPointTests {
    @Test(arguments: [
        (1, 2, false, 0x00), (1, 2, true, 0x80), (0, 0, false, 0x00), (0, 0, true, 0x00), (5, 0, true, 0x00),
    ] as [(UInt8, UInt8, Bool, UInt8)])
    func `Points compress with the sign of y`(x: UInt8, y: UInt8, negated: Bool, firstByte: UInt8) throws {
        let compressed = try ProofPoint.compressed(x: fieldElement(x), y: fieldElement(y), negated: negated)

        #expect(compressed == [firstByte] + fieldElement(x).dropFirst())
    }

    @Test(arguments: [
        ("183227397098d014dc2822db40c0ac2ecbc0b548b438e5469e10460b6c3e7ea3", 0x00),
        ("183227397098d014dc2822db40c0ac2ecbc0b548b438e5469e10460b6c3e7ea4", 0x80),
    ] as [(String, UInt8)])
    func `The flag starts above half the modulus`(y: String, firstByte: UInt8) throws {
        #expect(try ProofPoint.compressed(x: fieldElement(1), y: fixtureBytes(y))[0] == firstByte)
    }

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
}
