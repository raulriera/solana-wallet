import CryptoKit
@testable import Privacy
import Testing

struct P256ScalarTests {
    @Test(arguments: [
        (
            "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001",
            "0000000000000000000000000000000000000000000000000000000000000001"
        ),
        (
            "00000000000000000000000000000000ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550",
            "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550"
        ),
        (
            "00000000000000000000000000000000ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632552",
            "0000000000000000000000000000000000000000000000000000000000000001"
        ),
        (
            "000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000",
            "00000000ffffffff00000000000000004319055258e8617b0c46353d039cdaaf"
        ),
        (
            "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            "431905529c0166ce652e96b7ccca0a99679b73e19ad16947f01cf013fc632550"
        ),
        (
            "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f30",
            "185bb819b6065810af9bb667d1070711af70bf5a9ee0802ebfa3354ec1926898"
        ),
    ])
    func `Key material reduces to independently derived scalars`(keyMaterial: String, scalar: String) throws {
        let key = try P256Scalar.privateKey(reducing: fixtureBytes(keyMaterial))

        #expect(Array(key.rawRepresentation) == (try fixtureBytes(scalar)))
    }

    @Test(arguments: [
        "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        "00000000000000000000000000000000ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551",
        "00000000000000000000000000000001fffffffe00000001ffffffffffffffff79cdf55b4e2f3d09e7739585f8c64aa2",
    ])
    func `Multiples of the order are rejected`(keyMaterial: String) throws {
        let bytes = try fixtureBytes(keyMaterial)

        #expect(throws: P256Scalar.ValidationError.zeroScalar) {
            try P256Scalar.privateKey(reducing: bytes)
        }
    }
}
