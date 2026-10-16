import ModularArithmetic
import Testing

/// Verifies that the BN254 base field uses the curve's field modulus from EIP-196.
struct BN254BaseFieldTests {
    /// Verifies that the modulus is p = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47,
    /// the field modulus that EIP-196 specifies.
    ///
    /// Canonical decoding accepts exactly the values below the modulus m. Accepting p - 1, p with
    /// its last byte decremented, gives m > p - 1, and rejecting p gives m ≤ p, so m = p. Reducing p
    /// through the Montgomery arithmetic also gives zero, as m divides it.
    @Test
    func `The modulus is the field modulus p from EIP-196`() throws {
        let p = try fixtureBytes(FieldFixture.bn254Base.modulus)

        #expect(FieldElement<BN254BaseField>(bigEndianBytes: try fixtureBytes(FieldFixture.bn254Base.modulusMinusOne)) != nil)
        #expect(FieldElement<BN254BaseField>(bigEndianBytes: p) == nil)
        #expect(FieldElement<BN254BaseField>(reducing: p).bigEndianBytes == (try fixtureBytes(FieldFixture.zero)))
    }
}
