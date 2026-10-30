import ModularArithmetic
import Testing

struct P256ScalarFieldTests {
    @Test
    func `The modulus is the base point order n from SEC 2`() throws {
        let n = try fixtureBytes(FieldFixture.p256.modulus)

        #expect(FieldElement<P256ScalarField>(bigEndianBytes: try fixtureBytes(FieldFixture.p256.modulusMinusOne)) != nil)
        #expect(FieldElement<P256ScalarField>(bigEndianBytes: n) == nil)
        #expect(FieldElement<P256ScalarField>(reducing: n).bigEndianBytes == (try fixtureBytes(FieldFixture.zero)))
    }
}
