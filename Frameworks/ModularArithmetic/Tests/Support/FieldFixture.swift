import ModularArithmetic
import Testing

/// A field under test with values derived by hand from its modulus m.
///
/// Every value is 64 big-endian hexadecimal digits. Each property documents its derivation.
struct FieldFixture: Sendable, CustomTestStringConvertible {
    /// The field under test.
    let field: any PrimeField.Type
    /// The field's name in test results.
    let testDescription: String
    /// m, copied from the field's specification.
    let modulus: String
    /// m - 1: m with its last byte decremented. It is -1, its own inverse.
    let modulusMinusOne: String
    /// m - 2: m - 1 decremented once more.
    let modulusMinusTwo: String
    /// m + 1: m with its last byte incremented.
    let modulusPlusOne: String
    /// (m + 1) / 2, by halving m + 1 digit by digit. Doubling it gives m + 1, so it is the inverse of two.
    let half: String
    /// A value below 2^256 written as a known multiple of m plus a remainder, and that remainder.
    let multiple: Reduction
    /// (2^256 - 1) mod m: the bitwise complement of the largest multiple of m below 2^256.
    let maximumRemainder: String
    /// Values below m with all-ones limbs or a top bit that only this field's modulus allows.
    let fieldEdgeValues: [String]

    /// Values below m at limb boundaries and near the modulus.
    var edgeValues: [String] {
        Self.sharedEdgeValues + [modulusMinusOne, modulusMinusTwo, half] + fieldEdgeValues
    }

    /// A 32-byte value and its remainder modulo a field's modulus.
    struct Reduction: Sendable, CustomTestStringConvertible {
        /// The value to reduce.
        let value: String
        /// Its remainder modulo the field's modulus.
        let remainder: String

        /// The value to reduce, in test results.
        var testDescription: String { value }
    }
}

extension FieldFixture {
    /// Every field the module provides.
    static let all: [Self] = [bn254, p256]

    /// Zero.
    static let zero = "0000000000000000000000000000000000000000000000000000000000000000"
    /// One.
    static let one = "0000000000000000000000000000000000000000000000000000000000000001"
    /// Two.
    static let two = "0000000000000000000000000000000000000000000000000000000000000002"
    /// 2^64 - 1, the largest single-limb value.
    static let maximumLimb = "000000000000000000000000000000000000000000000000ffffffffffffffff"
    /// 2^64, the lowest bit of limb 1.
    static let twoToThe64 = "0000000000000000000000000000000000000000000000010000000000000000"
    /// 2^128 - 1, the largest two-limb value.
    static let maximumTwoLimbs = "00000000000000000000000000000000ffffffffffffffffffffffffffffffff"
    /// 2^128, the lowest bit of limb 2.
    static let twoToThe128 = "0000000000000000000000000000000100000000000000000000000000000000"
    /// 2^192 - 1, the largest three-limb value.
    static let maximumThreeLimbs = "0000000000000000ffffffffffffffffffffffffffffffffffffffffffffffff"
    /// 2^192, the lowest bit of limb 3.
    static let twoToThe192 = "0000000000000001000000000000000000000000000000000000000000000000"
    /// 2^255, the top bit of limb 3.
    static let twoToThe255 = "8000000000000000000000000000000000000000000000000000000000000000"
    /// 2^256 - 1, the largest 32-byte value.
    static let maximum = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

    /// 2^0, 2^64, 2^128, and 2^192: the lowest bit of each limb.
    static let limbBoundaries = [one, twoToThe64, twoToThe128, twoToThe192]

    /// 0, 2, 2^64 - 1, 2^128 - 1, 2^192 - 1, and the limb boundaries, which are below both moduli.
    static let sharedEdgeValues = [
        zero,
        two,
        maximumLimb,
        maximumTwoLimbs,
        maximumThreeLimbs,
    ] + limbBoundaries

    /// Encodes an integer below 2^128 as 32 big-endian bytes.
    ///
    /// Every such integer is below both moduli, so these are also its canonical bytes in either field.
    ///
    /// - Parameter value: The integer to encode.
    /// - Returns: 16 zero bytes, then the value's 16 big-endian bytes.
    static func bytes(of value: UInt128) -> [UInt8] {
        [UInt8](repeating: 0, count: 16) + stride(from: 120, through: 0, by: -8).map { UInt8(truncatingIfNeeded: value >> $0) }
    }

    /// The BN254 scalar field, whose modulus r is below 2^254.
    static let bn254 = Self(
        field: BN254ScalarField.self,
        testDescription: "BN254 scalar field",
        modulus: "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001",
        modulusMinusOne: "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000000",
        modulusMinusTwo: "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593efffffff",
        modulusPlusOne: "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000002",
        half: "183227397098d014dc2822db40c0ac2e9419f4243cdcb848a1f0fac9f8000001",
        // 5r by long multiplication, plus 7. 6r exceeds 2^256, so 5r is the largest multiple below it.
        multiple: Reduction(
            value: "f1f5883e65f820d099915c908786b9d1c903896a609f32d65369cbe3b000000c",
            remainder: "0000000000000000000000000000000000000000000000000000000000000007"
        ),
        // 2^256 - 1 - 5r, the complement of 5r = 0xf1f5…b0000005.
        maximumRemainder: "0e0a77c19a07df2f666ea36f7879462e36fc76959f60cd29ac96341c4ffffffa",
        // r's top limb minus one, above three all-ones limbs.
        fieldEdgeValues: ["30644e72e131a028ffffffffffffffffffffffffffffffffffffffffffffffff"]
    )

    /// The P-256 scalar field, whose modulus n is above 2^255.
    static let p256 = Self(
        field: P256ScalarField.self,
        testDescription: "P-256 scalar field",
        modulus: "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551",
        modulusMinusOne: "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550",
        modulusMinusTwo: "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc63254f",
        modulusPlusOne: "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632552",
        half: "7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a9",
        // n + 2^64 - 1: the lowest limb wraps to 0xf3b9cac2fc632550 and carries one into the next.
        // 2n exceeds 2^256, so n is the only nonzero multiple below it.
        multiple: Reduction(
            value: "ffffffff00000000ffffffffffffffffbce6faada7179e85f3b9cac2fc632550",
            remainder: maximumLimb
        ),
        // 2^256 - 1 - n, the complement of n.
        maximumRemainder: "00000000ffffffff00000000000000004319055258e8617b0c46353d039cdaae",
        fieldEdgeValues: [
            // 2^255, below n only.
            twoToThe255,
            // n's top two limbs, its second limb minus one, and an all-ones lowest limb.
            "ffffffff00000000ffffffffffffffffbce6faada7179e83ffffffffffffffff",
        ]
    )
}

extension FieldElement {
    /// Decodes a canonical fixture value.
    ///
    /// - Parameter hex: 64 big-endian hexadecimal digits encoding a value below the modulus.
    /// - Throws: A test failure if the value is malformed or not canonical.
    init(hex: String) throws {
        self = try #require(Self(bigEndianBytes: fixtureBytes(hex)))
    }
}
