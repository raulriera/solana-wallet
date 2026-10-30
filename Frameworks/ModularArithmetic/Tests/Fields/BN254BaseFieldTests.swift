import ModularArithmetic
import Testing

struct BN254BaseFieldTests {
    @Test
    func `The modulus is the field modulus p from EIP-196`() throws {
        let p = try fixtureBytes(FieldFixture.bn254Base.modulus)

        #expect(FieldElement<BN254BaseField>(bigEndianBytes: try fixtureBytes(FieldFixture.bn254Base.modulusMinusOne)) != nil)
        #expect(FieldElement<BN254BaseField>(bigEndianBytes: p) == nil)
        #expect(FieldElement<BN254BaseField>(reducing: p).bigEndianBytes == (try fixtureBytes(FieldFixture.zero)))
    }
}
