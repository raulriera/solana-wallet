@testable import ModularArithmetic
import Testing

struct ModulusTests {
    private typealias Element = FieldElement<LargestPrimeField>

    @Test(arguments: [
        (1, 1, 1), (1, 2, 2), (2, 2, 4),
        (0xffff_ffff, 0xffff_ffff, 0xffff_fffe_0000_0001),
    ] as [(UInt64, UInt64, UInt64)])
    func `Products of values just below a modulus near 2^256 carry through both extra limbs`(a: UInt64, b: UInt64, product: UInt64) {
        #expect((-Element(a) * -Element(b)).bigEndianBytes == FieldFixture.bytes(of: UInt128(product)))
    }

    @Test
    func `Minus one is its own inverse modulo a prime near 2^256`() throws {
        let minusOne = try fixtureBytes("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff42")
        #expect((-Element.one).inverse().bigEndianBytes == minusOne)
    }
}

private enum LargestPrimeField: PrimeField {
    static let modulus = Modulus(0xffff_ffff_ffff_ff43, .max, .max, .max)
}
