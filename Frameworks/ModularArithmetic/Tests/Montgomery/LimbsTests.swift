@testable import ModularArithmetic
import Testing

/// Verifies 256-bit limb arithmetic directly, with values derived by hand at limb boundaries and
/// from each field's modulus.
///
/// Results are compared limb by limb, so the checks don't depend on the equality of ``Limbs``.
struct LimbsTests {
    /// Verifies that values convert to and from 32 big-endian bytes at limb boundaries.
    ///
    /// Limb k holds bits 64k to 64k + 63, so 2^(64k) is a one in limb k alone, 2^(64k) - 1 is all
    /// ones below it, and 2^(64k + 63) is the top bit of limb k. The bytes list the most significant
    /// limb first, each limb big-endian, so the limbs 0x0001…07, 0x08…0f, 0x10…17, and 0x18…1f, from
    /// most significant, read as the bytes 0 to 31 in order.
    ///
    /// - Parameters:
    ///   - limbs: A value, least significant limb first.
    ///   - hex: The value's 32 big-endian bytes.
    @Test(arguments: [
        (Limbs.zero, FieldFixture.zero),
        (Limbs(1, 0, 0, 0), FieldFixture.one),
        (Limbs(1 << 63, 0, 0, 0), "0000000000000000000000000000000000000000000000008000000000000000"),
        (Limbs(.max, 0, 0, 0), FieldFixture.maximumLimb),
        (Limbs(0, 1, 0, 0), FieldFixture.twoToThe64),
        (Limbs(.max, .max, 0, 0), FieldFixture.maximumTwoLimbs),
        (Limbs(0, 0, 1, 0), FieldFixture.twoToThe128),
        (Limbs(.max, .max, .max, 0), FieldFixture.maximumThreeLimbs),
        (Limbs(0, 0, 0, 1), FieldFixture.twoToThe192),
        (Limbs(0, 0, 0, 1 << 63), FieldFixture.twoToThe255),
        (Limbs(.max, .max, .max, .max), FieldFixture.maximum),
        (
            Limbs(0x1819_1a1b_1c1d_1e1f, 0x1011_1213_1415_1617, 0x0809_0a0b_0c0d_0e0f, 0x0001_0203_0405_0607),
            "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        ),
    ] as [(Limbs, String)])
    func `Values round-trip through big-endian bytes at limb boundaries`(_ limbs: Limbs, hex: String) throws {
        let bytes = try fixtureBytes(hex)

        #expect(limbs.bigEndianBytes == bytes)
        #expect(Limbs(bigEndianBytes: bytes).words == limbs.words)
    }

    /// Verifies that equality compares every limb.
    ///
    /// The first eight values differ from zero in one bit of one limb: the lowest or the highest bit
    /// of limb 0, 1, 2, or 3. The last three set the top bit of two adjacent limbs, so an equality
    /// that combined the limb differences with XOR or wrapping addition instead of OR would let the
    /// two differences cancel and call the value equal to zero. Each value equals a copy built from
    /// its own limbs.
    ///
    /// - Parameter value: A value that differs from zero.
    @Test(arguments: [
        Limbs(1, 0, 0, 0), Limbs(0, 1, 0, 0), Limbs(0, 0, 1, 0), Limbs(0, 0, 0, 1),
        Limbs(1 << 63, 0, 0, 0), Limbs(0, 1 << 63, 0, 0), Limbs(0, 0, 1 << 63, 0), Limbs(0, 0, 0, 1 << 63),
        Limbs(1 << 63, 1 << 63, 0, 0), Limbs(0, 1 << 63, 1 << 63, 0), Limbs(0, 0, 1 << 63, 1 << 63),
    ])
    func `Equality compares every limb`(_ value: Limbs) {
        #expect(value != .zero)
        #expect(Limbs.zero != value)
        #expect(value == Limbs(value.limb0, value.limb1, value.limb2, value.limb3))
    }

    /// Verifies that selection returns the first value for a condition of one and the second for zero.
    ///
    /// The two values are bitwise complements in every limb, and every limb of each is nonzero, so a
    /// wrong or missing mask in any limb would change the result.
    @Test
    func `Selection chooses the first value for one and the second for zero`() {
        let first = Limbs(0x0123_4567_89ab_cdef, 0xfedc_ba98_7654_3210, 0x0f0f_0f0f_0f0f_0f0f, 0xf0f0_f0f0_f0f0_f0f0)
        let second = Limbs(0xfedc_ba98_7654_3210, 0x0123_4567_89ab_cdef, 0xf0f0_f0f0_f0f0_f0f0, 0x0f0f_0f0f_0f0f_0f0f)

        #expect(Limbs.select(1, first, second).words == first.words)
        #expect(Limbs.select(0, first, second).words == second.words)
    }

    /// Verifies that addition carries across every limb and out of the top limb.
    ///
    /// - (1, 2, 3, 4) + (5, 6, 7, 8) = (6, 8, 10, 12) adds limb by limb without carries.
    /// - (2^64 - 1) × 2^(64k) + 2^(64k) = 2^(64(k + 1)) carries from limb k into limb k + 1 alone.
    /// - 2^255 + 2^255 = 2^256 carries out of the top limb alone.
    /// - (2^256 - 1) + 1 = 2^256 carries through every limb and out of the top.
    /// - (2^256 - 1) + (2^256 - 1) = 2^256 + (2^256 - 2), whose lowest limb is 2^64 - 2.
    ///
    /// - Parameters:
    ///   - augend: A value.
    ///   - addend: The value to add.
    ///   - sum: The low 256 bits of the sum.
    ///   - carry: The bit above them.
    @Test(arguments: [
        (Limbs(1, 2, 3, 4), Limbs(5, 6, 7, 8), Limbs(6, 8, 10, 12), 0),
        (Limbs(.max, 0, 0, 0), Limbs(1, 0, 0, 0), Limbs(0, 1, 0, 0), 0),
        (Limbs(0, .max, 0, 0), Limbs(0, 1, 0, 0), Limbs(0, 0, 1, 0), 0),
        (Limbs(0, 0, .max, 0), Limbs(0, 0, 1, 0), Limbs(0, 0, 0, 1), 0),
        (Limbs(0, 0, 0, 1 << 63), Limbs(0, 0, 0, 1 << 63), Limbs.zero, 1),
        (Limbs(.max, .max, .max, .max), Limbs(1, 0, 0, 0), Limbs.zero, 1),
        (Limbs(.max, .max, .max, .max), Limbs(.max, .max, .max, .max), Limbs(.max - 1, .max, .max, .max), 1),
    ] as [(Limbs, Limbs, Limbs, UInt64)])
    func `Addition carries across every limb and out of the top limb`(_ augend: Limbs, _ addend: Limbs, sum: Limbs, carry: UInt64) {
        let result = augend.adding(addend)

        #expect(result.sum.words == sum.words)
        #expect(result.carry == carry)
    }

    /// Verifies that subtraction borrows across every limb and out of the top limb.
    ///
    /// - (6, 8, 10, 12) - (5, 6, 7, 8) = (1, 2, 3, 4) subtracts limb by limb without borrows.
    /// - 2^(64(k + 1)) - 2^(64k) = (2^64 - 1) × 2^(64k) borrows from limb k + 1 into limb k alone.
    /// - 0 - 2^192 = 2^256 - 2^192, all ones in the top limb, borrows out of the top limb alone.
    /// - 0 - 1 = 2^256 - 1 borrows through every limb and out of the top.
    /// - 0 - (2^256 - 1) = 1 - 2^256 also borrows out of the top and leaves one.
    /// - (2^256 - 1) - (2^256 - 1) = 0 without a borrow.
    ///
    /// - Parameters:
    ///   - minuend: A value.
    ///   - subtrahend: The value to subtract.
    ///   - difference: The difference modulo 2^256.
    ///   - borrow: One if the subtrahend exceeds the minuend.
    @Test(arguments: [
        (Limbs(6, 8, 10, 12), Limbs(5, 6, 7, 8), Limbs(1, 2, 3, 4), 0),
        (Limbs(0, 1, 0, 0), Limbs(1, 0, 0, 0), Limbs(.max, 0, 0, 0), 0),
        (Limbs(0, 0, 1, 0), Limbs(0, 1, 0, 0), Limbs(0, .max, 0, 0), 0),
        (Limbs(0, 0, 0, 1), Limbs(0, 0, 1, 0), Limbs(0, 0, .max, 0), 0),
        (Limbs.zero, Limbs(0, 0, 0, 1), Limbs(0, 0, 0, .max), 1),
        (Limbs.zero, Limbs(1, 0, 0, 0), Limbs(.max, .max, .max, .max), 1),
        (Limbs.zero, Limbs(.max, .max, .max, .max), Limbs(1, 0, 0, 0), 1),
        (Limbs(.max, .max, .max, .max), Limbs(.max, .max, .max, .max), Limbs.zero, 0),
    ] as [(Limbs, Limbs, Limbs, UInt64)])
    func `Subtraction borrows across every limb and out of the top limb`(_ minuend: Limbs, _ subtrahend: Limbs, difference: Limbs, borrow: UInt64) {
        let result = minuend.subtracting(subtrahend)

        #expect(result.difference.words == difference.words)
        #expect(result.borrow == borrow)
    }

    /// Verifies that reduction leaves each value below twice the modulus at its remainder.
    ///
    /// For every modulus m, m - 1 stays, m leaves 0, and m + 1 leaves 1. The other values come from
    /// each modulus, as ``FieldFixture`` documents:
    /// - BN254: 2r - 1 = 0x60c8…e0000001, r doubled digit by digit less one, leaves r - 1.
    /// - BN254 base field: 2p - 1 = 0x60c8…b0f9fa8d, p doubled digit by digit less one, leaves p - 1.
    /// - P-256, whose n exceeds 2^255, so values below 2n can carry above 2^256:
    ///   - 2^256 - 1, without a carry, leaves 2^256 - 1 - n, the complement of n.
    ///   - 2^256, a carry above zero limbs, leaves 2^256 - n, the complement of n plus one. Without
    ///     its carry the value would be zero.
    ///   - 2n - 1 = 2^256 + 0xfffffffe…f8c64aa1, n doubled digit by digit with its top bit carried
    ///     out, less one, leaves n - 1. Its low limbs alone are below n.
    ///
    /// - Parameters:
    ///   - fixture: The field whose modulus reduces the value.
    ///   - carry: The bit above the value's four limbs.
    ///   - value: The value's low 256 bits.
    ///   - remainder: The value modulo the field's modulus.
    @Test(arguments: [
        (FieldFixture.bn254, 0, FieldFixture.bn254.modulusMinusOne, FieldFixture.bn254.modulusMinusOne),
        (FieldFixture.bn254, 0, FieldFixture.bn254.modulus, FieldFixture.zero),
        (FieldFixture.bn254, 0, FieldFixture.bn254.modulusPlusOne, FieldFixture.one),
        (
            FieldFixture.bn254, 0, "60c89ce5c263405370a08b6d0302b0ba5067d090f372e12287c3eb27e0000001",
            FieldFixture.bn254.modulusMinusOne
        ),
        (FieldFixture.bn254Base, 0, FieldFixture.bn254Base.modulusMinusOne, FieldFixture.bn254Base.modulusMinusOne),
        (FieldFixture.bn254Base, 0, FieldFixture.bn254Base.modulus, FieldFixture.zero),
        (FieldFixture.bn254Base, 0, FieldFixture.bn254Base.modulusPlusOne, FieldFixture.one),
        (
            FieldFixture.bn254Base, 0, "60c89ce5c263405370a08b6d0302b0bb2f02d522d0e3951a7841182db0f9fa8d",
            FieldFixture.bn254Base.modulusMinusOne
        ),
        (FieldFixture.p256, 0, FieldFixture.p256.modulusMinusOne, FieldFixture.p256.modulusMinusOne),
        (FieldFixture.p256, 0, FieldFixture.p256.modulus, FieldFixture.zero),
        (FieldFixture.p256, 0, FieldFixture.p256.modulusPlusOne, FieldFixture.one),
        (FieldFixture.p256, 0, FieldFixture.maximum, FieldFixture.p256.maximumRemainder),
        (
            FieldFixture.p256, 1, FieldFixture.zero,
            "00000000ffffffff00000000000000004319055258e8617b0c46353d039cdaaf"
        ),
        (
            FieldFixture.p256, 1, "fffffffe00000001ffffffffffffffff79cdf55b4e2f3d09e7739585f8c64aa1",
            FieldFixture.p256.modulusMinusOne
        ),
    ] as [(FieldFixture, UInt64, String, String)])
    func `Reduction leaves values below twice the modulus at their remainder`(
        _ fixture: FieldFixture, carry: UInt64, value: String, remainder: String
    ) throws {
        let modulus = try Limbs(hex: fixture.modulus)

        #expect(try Limbs(hex: value).reduced(carry: carry, modulo: modulus).words == Limbs(hex: remainder).words)
    }

    /// Verifies that modular addition wraps at the modulus.
    ///
    /// 1 + 1 = 2 stays below m. (m - 1) + 1 = m ≡ 0. (m + 1) / 2 doubled is m + 1 ≡ 1.
    /// (m - 1) + (m - 1) = 2m - 2 ≡ m - 2, which carries above 2^256 for P-256.
    ///
    /// - Parameter fixture: A field and values derived from its modulus.
    @Test(arguments: FieldFixture.all)
    func `Modular addition wraps at the modulus`(_ fixture: FieldFixture) throws {
        let modulus = try Limbs(hex: fixture.modulus)
        let minusOne = try Limbs(hex: fixture.modulusMinusOne)
        let half = try Limbs(hex: fixture.half)
        let one = Limbs(1, 0, 0, 0)

        #expect(one.adding(one, modulo: modulus).words == [2, 0, 0, 0])
        #expect(minusOne.adding(one, modulo: modulus).words == [0, 0, 0, 0])
        #expect(half.adding(half, modulo: modulus).words == [1, 0, 0, 0])
        #expect(minusOne.adding(minusOne, modulo: modulus).words == (try Limbs(hex: fixture.modulusMinusTwo)).words)
    }

    /// Verifies that modular subtraction wraps at the modulus.
    ///
    /// 2 - 1 = 1 stays below m. 0 - 1 ≡ m - 1. 1 - (m - 1) = 2 - m ≡ 2. (m - 1) - (m - 1) = 0.
    ///
    /// - Parameter fixture: A field and values derived from its modulus.
    @Test(arguments: FieldFixture.all)
    func `Modular subtraction wraps at the modulus`(_ fixture: FieldFixture) throws {
        let modulus = try Limbs(hex: fixture.modulus)
        let minusOne = try Limbs(hex: fixture.modulusMinusOne)
        let one = Limbs(1, 0, 0, 0)

        #expect(Limbs(2, 0, 0, 0).subtracting(one, modulo: modulus).words == [1, 0, 0, 0])
        #expect(Limbs.zero.subtracting(one, modulo: modulus).words == minusOne.words)
        #expect(one.subtracting(minusOne, modulo: modulus).words == [2, 0, 0, 0])
        #expect(minusOne.subtracting(minusOne, modulo: modulus).words == [0, 0, 0, 0])
    }

    /// Verifies that limb addition returns the low 64 bits and the carry.
    ///
    /// With M = 2^64: 1 + 2 = 3; 0 + 0 + 1 = 1; (M - 1) + 1 = M and (M - 1) + 0 + 1 = M carry
    /// with zero low bits; (M - 1) + (M - 1) = M + (M - 2); and the largest sum,
    /// (M - 1) + (M - 1) + 1 = M + (M - 1).
    ///
    /// - Parameters:
    ///   - augend: A limb.
    ///   - addend: The limb to add.
    ///   - carryIn: The carry from the previous limb.
    ///   - sum: The low 64 bits of the sum.
    ///   - carry: The carry into the next limb.
    @Test(arguments: [
        (1, 2, 0, 3, 0),
        (0, 0, 1, 1, 0),
        (.max, 1, 0, 0, 1),
        (.max, 0, 1, 0, 1),
        (.max, .max, 0, .max - 1, 1),
        (.max, .max, 1, .max, 1),
    ] as [(UInt64, UInt64, UInt64, UInt64, UInt64)])
    func `Limb addition returns the low bits and the carry`(_ augend: UInt64, _ addend: UInt64, carryIn: UInt64, sum: UInt64, carry: UInt64) {
        let result = augend.adding(addend, carry: carryIn)

        #expect(result.0 == sum)
        #expect(result.carry == carry)
    }

    /// Verifies that limb subtraction returns the difference modulo 2^64 and the borrow.
    ///
    /// With M = 2^64: 5 - 3 - 1 = 1; 1 - 0 - 1 = 0; (M - 1) - (M - 1) = 0; 0 - 1 and 0 - 0 - 1 wrap
    /// to M - 1; (M - 1) - (M - 1) - 1 = -1 wraps to M - 1; and the most negative difference,
    /// 0 - (M - 1) - 1 = -M, wraps to zero, still with a borrow.
    ///
    /// - Parameters:
    ///   - minuend: A limb.
    ///   - subtrahend: The limb to subtract.
    ///   - borrowIn: The borrow from the previous limb.
    ///   - difference: The difference modulo 2^64.
    ///   - borrow: One if the subtraction wrapped.
    @Test(arguments: [
        (5, 3, 1, 1, 0),
        (1, 0, 1, 0, 0),
        (.max, .max, 0, 0, 0),
        (0, 1, 0, .max, 1),
        (0, 0, 1, .max, 1),
        (.max, .max, 1, .max, 1),
        (0, .max, 1, 0, 1),
    ] as [(UInt64, UInt64, UInt64, UInt64, UInt64)])
    func `Limb subtraction returns the difference and the borrow`(_ minuend: UInt64, _ subtrahend: UInt64, borrowIn: UInt64, difference: UInt64, borrow: UInt64) {
        let result = minuend.subtracting(subtrahend, borrow: borrowIn)

        #expect(result.0 == difference)
        #expect(result.borrow == borrow)
    }

    /// Verifies that a limb product with two added limbs returns the low 64 bits and the carry.
    ///
    /// With M = 2^64: 3 × 5 + 7 + 11 = 33; 2^32 × 2^32 = M; (M - 1) × 2 = M + (M - 2);
    /// (M - 1)² = M² - 2M + 1 = (M - 2) × M + 1; 0 × (M - 1) + 2(M - 1) = M + (M - 2); and the
    /// largest result, (M - 1)² + 2(M - 1) = M² - 1, has all ones in both halves.
    ///
    /// - Parameters:
    ///   - multiplicand: A limb.
    ///   - multiplier: The limb to multiply by.
    ///   - addend: A limb to add to the product.
    ///   - carryIn: The carry from the previous limb.
    ///   - low: The low 64 bits of the result.
    ///   - carry: The high 64 bits, the carry into the next limb.
    @Test(arguments: [
        (3, 5, 7, 11, 33, 0),
        (1 << 32, 1 << 32, 0, 0, 0, 1),
        (.max, 2, 0, 0, .max - 1, 1),
        (.max, .max, 0, 0, 1, .max - 1),
        (0, .max, .max, .max, .max - 1, 1),
        (.max, .max, .max, .max, .max, .max),
    ] as [(UInt64, UInt64, UInt64, UInt64, UInt64, UInt64)])
    func `Limb multiplication with two addends returns the low bits and the carry`(
        _ multiplicand: UInt64, _ multiplier: UInt64, addend: UInt64, carryIn: UInt64, low: UInt64, carry: UInt64
    ) {
        let result = multiplicand.multiplied(by: multiplier, adding: addend, carry: carryIn)

        #expect(result.0 == low)
        #expect(result.carry == carry)
    }
}

private extension Limbs {
    /// The limbs, least significant first, for comparisons that don't rely on `==`.
    var words: [UInt64] {
        [limb0, limb1, limb2, limb3]
    }

    /// Reads a fixture value.
    ///
    /// - Parameter hex: 64 big-endian hexadecimal digits.
    /// - Throws: A test failure if the value is malformed.
    init(hex: String) throws {
        self.init(bigEndianBytes: try fixtureBytes(hex))
    }
}
