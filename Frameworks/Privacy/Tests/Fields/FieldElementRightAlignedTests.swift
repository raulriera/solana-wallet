import ModularArithmetic
@testable import Privacy
import Testing

/// Verifies the reduction of right-aligned big-endian bytes to field elements.
struct FieldElementRightAlignedTests {
    /// Verifies that bytes reduce as the lowest-order bytes of a 32-byte big-endian value.
    ///
    /// The cases are in the BN254 scalar field: no bytes, which are zero; one and two bytes, whose
    /// order and alignment the small integers check; eight bytes, the largest UInt64; and the
    /// 32-byte values r and r + 1, which reduce to 0 and 1.
    ///
    /// - Parameters:
    ///   - hex: At most 32 big-endian bytes.
    ///   - value: The expected element, as an integer.
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
