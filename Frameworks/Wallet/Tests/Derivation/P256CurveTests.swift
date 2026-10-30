import Testing
@testable import Wallet

struct P256CurveTests {
    private static let order = "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551"

    private static let orderMinusOne = "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550"

    private static let maximum = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

    private static let parent = "612091aaa12e22dd2abef664f8a01a82cae99ad7441b7ef8110424915c268bc2"

    @Test(arguments: [
        "0000000000000000000000000000000000000000000000000000000000000000", order, maximum,
    ])
    func `Master candidates of zero or at least n are refused`(candidate: String) throws {
        #expect(P256Curve().privateKey(candidate: try fixtureBytes(candidate), parent: nil) == nil)
    }

    @Test(arguments: ["0000000000000000000000000000000000000000000000000000000000000001", orderMinusOne])
    func `Master candidates from one to n minus one are accepted unchanged`(candidate: String) throws {
        let bytes = try fixtureBytes(candidate)

        #expect(P256Curve().privateKey(candidate: bytes, parent: nil) == bytes)
    }

    @Test(arguments: [order, maximum, "9edf6e545ed1dd23d541099b075fe57cf1fd5fd662fc1f8ce2b5a631a03c998f"])
    func `Child candidates of at least n or summing to zero are refused`(candidate: String) throws {
        #expect(P256Curve().privateKey(candidate: try fixtureBytes(candidate), parent: try fixtureBytes(Self.parent)) == nil)
    }

    @Test(arguments: [
        (orderMinusOne, "612091aaa12e22dd2abef664f8a01a82cae99ad7441b7ef8110424915c268bc1"),
        ("0000000000000000000000000000000000000000000000000000000000000001",
         "612091aaa12e22dd2abef664f8a01a82cae99ad7441b7ef8110424915c268bc3"),
        ("f000000000000000000000000000000000000000000000000000000000000000",
         "512091aba12e22dc2abef664f8a01a830e02a0299d03e0731d4a59ce5fc36671"),
    ])
    func `Child keys are the candidate plus the parent modulo n`(candidate: String, expected: String) throws {
        let key = P256Curve().privateKey(candidate: try fixtureBytes(candidate), parent: try fixtureBytes(Self.parent))

        #expect(key == (try fixtureBytes(expected)))
    }
}
