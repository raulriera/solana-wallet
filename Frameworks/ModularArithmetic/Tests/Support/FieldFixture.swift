import ModularArithmetic
import Testing

struct FieldFixture: Sendable, CustomTestStringConvertible {
    let field: any PrimeField.Type
    let testDescription: String
    let modulus: String
    let modulusMinusOne: String
    let modulusMinusTwo: String
    let modulusPlusOne: String
    let half: String
    let multiple: Reduction
    let maximumRemainder: String
    let fieldEdgeValues: [String]

    var edgeValues: [String] {
        Self.sharedEdgeValues + [modulusMinusOne, modulusMinusTwo, half] + fieldEdgeValues
    }

    struct Reduction: Sendable, CustomTestStringConvertible {
        let value: String
        let remainder: String

        var testDescription: String { value }
    }
}

extension FieldFixture {
    static let all: [Self] = [bn254, bn254Base, p256]

    static let zero = "0000000000000000000000000000000000000000000000000000000000000000"
    static let one = "0000000000000000000000000000000000000000000000000000000000000001"
    static let two = "0000000000000000000000000000000000000000000000000000000000000002"
    static let maximumLimb = "000000000000000000000000000000000000000000000000ffffffffffffffff"
    static let twoToThe64 = "0000000000000000000000000000000000000000000000010000000000000000"
    static let maximumTwoLimbs = "00000000000000000000000000000000ffffffffffffffffffffffffffffffff"
    static let twoToThe128 = "0000000000000000000000000000000100000000000000000000000000000000"
    static let maximumThreeLimbs = "0000000000000000ffffffffffffffffffffffffffffffffffffffffffffffff"
    static let twoToThe192 = "0000000000000001000000000000000000000000000000000000000000000000"
    static let twoToThe255 = "8000000000000000000000000000000000000000000000000000000000000000"
    static let maximum = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

    static let limbBoundaries = [one, twoToThe64, twoToThe128, twoToThe192]

    static let sharedEdgeValues = [
        zero,
        two,
        maximumLimb,
        maximumTwoLimbs,
        maximumThreeLimbs,
    ] + limbBoundaries

    static func bytes(of value: UInt128) -> [UInt8] {
        [UInt8](repeating: 0, count: 16) + stride(from: 120, through: 0, by: -8).map { UInt8(truncatingIfNeeded: value >> $0) }
    }

    static let bn254 = Self(
        field: BN254ScalarField.self,
        testDescription: "BN254 scalar field",
        modulus: "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001",
        modulusMinusOne: "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000000",
        modulusMinusTwo: "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593efffffff",
        modulusPlusOne: "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000002",
        half: "183227397098d014dc2822db40c0ac2e9419f4243cdcb848a1f0fac9f8000001",
        multiple: Reduction(
            value: "f1f5883e65f820d099915c908786b9d1c903896a609f32d65369cbe3b000000c",
            remainder: "0000000000000000000000000000000000000000000000000000000000000007"
        ),
        maximumRemainder: "0e0a77c19a07df2f666ea36f7879462e36fc76959f60cd29ac96341c4ffffffa",
        fieldEdgeValues: ["30644e72e131a028ffffffffffffffffffffffffffffffffffffffffffffffff"]
    )

    static let bn254Base = Self(
        field: BN254BaseField.self,
        testDescription: "BN254 base field",
        modulus: "30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47",
        modulusMinusOne: "30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd46",
        modulusMinusTwo: "30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd45",
        modulusPlusOne: "30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd48",
        half: "183227397098d014dc2822db40c0ac2ecbc0b548b438e5469e10460b6c3e7ea4",
        multiple: Reduction(
            value: "f1f5883e65f820d099915c908786b9d3f58714d70a38f4c22ca2bc723a70f26a",
            remainder: "0000000000000000000000000000000000000000000000000000000000000007"
        ),
        maximumRemainder: "0e0a77c19a07df2f666ea36f7879462c0a78eb28f5c70b3dd35d438dc58f0d9c",
        fieldEdgeValues: ["30644e72e131a028ffffffffffffffffffffffffffffffffffffffffffffffff"]
    )

    static let p256 = Self(
        field: P256ScalarField.self,
        testDescription: "P-256 scalar field",
        modulus: "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551",
        modulusMinusOne: "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550",
        modulusMinusTwo: "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc63254f",
        modulusPlusOne: "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632552",
        half: "7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a9",
        multiple: Reduction(
            value: "ffffffff00000000ffffffffffffffffbce6faada7179e85f3b9cac2fc632550",
            remainder: maximumLimb
        ),
        maximumRemainder: "00000000ffffffff00000000000000004319055258e8617b0c46353d039cdaae",
        fieldEdgeValues: [
            twoToThe255,
            "ffffffff00000000ffffffffffffffffbce6faada7179e83ffffffffffffffff",
        ]
    )
}
