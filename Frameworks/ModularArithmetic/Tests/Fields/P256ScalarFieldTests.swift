import ModularArithmetic
import Testing

/// Verifies that the P-256 scalar field uses the base point's order from SEC 2.
struct P256ScalarFieldTests {
    /// Verifies that the modulus is n = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551,
    /// the order of the base point that SEC 2 specifies in section 2.4.2.
    ///
    /// Canonical decoding accepts exactly the values below the modulus m. Accepting n - 1, n with
    /// its last byte decremented, gives m > n - 1, and rejecting n gives m ≤ n, so m = n. Reducing n
    /// through the Montgomery arithmetic also gives zero, as m divides it.
    @Test
    func `The modulus is the base point order n from SEC 2`() throws {
        let n = try fixtureBytes(FieldFixture.p256.modulus)

        #expect(FieldElement<P256ScalarField>(bigEndianBytes: try fixtureBytes(FieldFixture.p256.modulusMinusOne)) != nil)
        #expect(FieldElement<P256ScalarField>(bigEndianBytes: n) == nil)
        #expect(FieldElement<P256ScalarField>(reducing: n).bigEndianBytes == (try fixtureBytes(FieldFixture.zero)))
    }
}
