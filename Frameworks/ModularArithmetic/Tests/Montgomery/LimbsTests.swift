@testable import ModularArithmetic
import Testing

struct LimbsTests {
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

    @Test
    func `Selection chooses the first value for one and the second for zero`() {
        let first = Limbs(0x0123_4567_89ab_cdef, 0xfedc_ba98_7654_3210, 0x0f0f_0f0f_0f0f_0f0f, 0xf0f0_f0f0_f0f0_f0f0)
        let second = Limbs(0xfedc_ba98_7654_3210, 0x0123_4567_89ab_cdef, 0xf0f0_f0f0_f0f0_f0f0, 0x0f0f_0f0f_0f0f_0f0f)

        #expect(Limbs.select(1, first, second).words == first.words)
        #expect(Limbs.select(0, first, second).words == second.words)
    }

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
        (FieldFixture.wide, 0, FieldFixture.wide.modulusMinusOne, FieldFixture.wide.modulusMinusOne),
        (FieldFixture.wide, 0, FieldFixture.wide.modulus, FieldFixture.zero),
        (FieldFixture.wide, 0, FieldFixture.wide.modulusPlusOne, FieldFixture.one),
        (FieldFixture.wide, 0, FieldFixture.maximum, FieldFixture.wide.maximumRemainder),
        (
            FieldFixture.wide, 1, FieldFixture.zero,
            "00000000ffffffff00000000000000004319055258e8617b0c46353d039cdaaf"
        ),
        (
            FieldFixture.wide, 1, "fffffffe00000001ffffffffffffffff79cdf55b4e2f3d09e7739585f8c64aa1",
            FieldFixture.wide.modulusMinusOne
        ),
    ] as [(FieldFixture, UInt64, String, String)])
    func `Reduction leaves values below twice the modulus at their remainder`(
        _ fixture: FieldFixture, carry: UInt64, value: String, remainder: String
    ) throws {
        let modulus = try Limbs(hex: fixture.modulus)

        #expect(try Limbs(hex: value).reduced(carry: carry, modulo: modulus).words == Limbs(hex: remainder).words)
    }

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
    var words: [UInt64] {
        [limb0, limb1, limb2, limb3]
    }

    init(hex: String) throws {
        self.init(bigEndianBytes: try fixtureBytes(hex))
    }
}
