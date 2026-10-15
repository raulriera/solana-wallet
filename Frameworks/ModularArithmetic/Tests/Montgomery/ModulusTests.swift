@testable import ModularArithmetic
import Testing

/// Verifies the second extra carry limb of Montgomery multiplication with a test-only field.
///
/// Each reduction step adds `a × word` to a running sum below `a + m`. That sum reaches 2^320, the
/// second limb above `a`, only when `word` is 2^64 - 1 and `a` exceeds 2^256 - 2^192. The BN254 and
/// P-256 moduli are below that bound, and neither field's R² mod m has an all-ones limb, so only a
/// modulus closer to 2^256 reaches this carry.
struct ModulusTests {
    /// An element of the test-only field.
    private typealias Element = FieldElement<LargestPrimeField>

    /// Verifies that products of negated small integers match the integer products.
    ///
    /// (-a) × (-b) = a × b. R mod m = 2^256 - m = 189, so the Montgomery form of -a is m - 189a,
    /// whose upper three limbs are all ones, and these products carry into the second extra limb.
    /// Each a × b is below 2^64, so its canonical bytes are the integer, left-padded with zero bytes.
    ///
    /// - Parameters:
    ///   - a: A small integer to negate.
    ///   - b: Another small integer to negate.
    ///   - product: The integer product a × b.
    @Test(arguments: [
        (1, 1, 1), (1, 2, 2), (2, 2, 4),
        (0xffff_ffff, 0xffff_ffff, 0xffff_fffe_0000_0001),
    ] as [(UInt64, UInt64, UInt64)])
    func `Products of values just below a modulus near 2^256 carry through both extra limbs`(a: UInt64, b: UInt64, product: UInt64) {
        #expect((-Element(a) * -Element(b)).bigEndianBytes == FieldFixture.bytes(of: UInt128(product)))
    }

    /// Verifies that minus one is its own inverse modulo a prime near 2^256.
    ///
    /// (-1) × (-1) = 1, so (m - 1)⁻¹ = m - 1 = 2^256 - 190: 31 bytes of 0xff, then 0x42. Raising -1 to
    /// m - 2 passes only through 1 and -1, so its products carry into the second extra limb hundreds
    /// of times.
    @Test
    func `Minus one is its own inverse modulo a prime near 2^256`() throws {
        let minusOne = try fixtureBytes("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff42")
        #expect((-Element.one).inverse().bigEndianBytes == minusOne)
    }
}

/// The field of integers modulo m = 2^256 - 189, the largest prime below 2^256.
///
/// m ≡ 3 mod 8, so the square of m's lowest limb is 9 modulo 16: the limb is its own inverse modulo
/// 2^3 only, and computing -m⁻¹ mod 2^64 needs all five Newton steps.
private enum LargestPrimeField: PrimeField {
    /// m: 2^64 - 189 = 0xffffffffffffff43 in the lowest limb, and all ones above it.
    static let modulus = Modulus(0xffff_ffff_ffff_ff43, .max, .max, .max)
}
