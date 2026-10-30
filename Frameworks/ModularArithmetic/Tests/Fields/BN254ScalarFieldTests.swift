import ModularArithmetic
import Testing

struct BN254ScalarFieldTests {
    @Test
    func `The modulus is the group order r from EIP-197`() throws {
        let r = try fixtureBytes(FieldFixture.bn254.modulus)

        #expect(FieldElement<BN254ScalarField>(bigEndianBytes: try fixtureBytes(FieldFixture.bn254.modulusMinusOne)) != nil)
        #expect(FieldElement<BN254ScalarField>(bigEndianBytes: r) == nil)
        #expect(FieldElement<BN254ScalarField>(reducing: r).bigEndianBytes == (try fixtureBytes(FieldFixture.zero)))
    }
}
