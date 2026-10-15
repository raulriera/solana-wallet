import ModularArithmetic
import Testing

/// Verifies that the BN254 scalar field uses the curve's group order from EIP-197.
struct BN254ScalarFieldTests {
    /// Verifies that the modulus is r = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001,
    /// the group order that EIP-197 specifies.
    ///
    /// Canonical decoding accepts exactly the values below the modulus m. Accepting r - 1, r with
    /// its last byte decremented, gives m > r - 1, and rejecting r gives m ≤ r, so m = r. Reducing r
    /// through the Montgomery arithmetic also gives zero, as m divides it.
    @Test
    func `The modulus is the group order r from EIP-197`() throws {
        let r = try fixtureBytes(FieldFixture.bn254.modulus)

        #expect(FieldElement<BN254ScalarField>(bigEndianBytes: try fixtureBytes(FieldFixture.bn254.modulusMinusOne)) != nil)
        #expect(FieldElement<BN254ScalarField>(bigEndianBytes: r) == nil)
        #expect(FieldElement<BN254ScalarField>(reducing: r).bigEndianBytes == (try fixtureBytes(FieldFixture.zero)))
    }
}
