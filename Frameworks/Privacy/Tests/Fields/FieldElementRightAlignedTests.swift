import ModularArithmetic
@testable import Privacy
import Testing

struct FieldElementRightAlignedTests {
    @Test(arguments: [
        ("", 0),
        ("01", 1),
        ("0102", 0x0102),
        ("ffffffffffffffff", .max),
        ("30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001", 0),
        ("30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000002", 1),
    ] as [(String, UInt64)])
    func `Bytes reduce as the lowest-order bytes of a 32-byte value`(hex: String, value: UInt64) throws {
        #expect(Poseidon.Element(reducingRightAligned: try fixtureBytes(hex)) == Poseidon.Element(value))
    }
}
