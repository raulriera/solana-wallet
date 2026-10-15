import Testing
@testable import Wallet

/// Verifies SLIP-0010's nist256p1 candidate rule directly, at the edges of the group order n.
///
/// n comes from SEC 2; values near it change its last byte. The parent k is SLIP-0010's first
/// nist256p1 master key. Expected sums come from Python's arbitrary-precision integers.
struct P256CurveTests {
    /// n, the order of the curve's base point.
    private static let order = "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551"

    /// n - 1, the largest private key.
    private static let orderMinusOne = "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550"

    /// 2^256 - 1, the largest 32-byte value.
    private static let maximum = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

    /// The parent private key k.
    private static let parent = "612091aaa12e22dd2abef664f8a01a82cae99ad7441b7ef8110424915c268bc2"

    /// Verifies that SLIP-0010 hashes again for a master candidate of 0 or at least n.
    ///
    /// - Parameter candidate: An invalid master candidate.
    @Test(arguments: [
        "0000000000000000000000000000000000000000000000000000000000000000", order, maximum,
    ])
    func `Master candidates of zero or at least n are refused`(candidate: String) throws {
        #expect(P256Curve().privateKey(candidate: try fixtureBytes(candidate), parent: nil) == nil)
    }

    /// Verifies that a master candidate from 1 to n - 1 is the master key.
    ///
    /// - Parameter candidate: A valid master candidate.
    @Test(arguments: ["0000000000000000000000000000000000000000000000000000000000000001", orderMinusOne])
    func `Master candidates from one to n minus one are accepted unchanged`(candidate: String) throws {
        let bytes = try fixtureBytes(candidate)

        #expect(P256Curve().privateKey(candidate: bytes, parent: nil) == bytes)
    }

    /// Verifies that SLIP-0010 hashes again for a child candidate of at least n, or one whose sum
    /// with the parent is 0 modulo n.
    ///
    /// n - k is the candidate whose sum with k is n.
    ///
    /// - Parameter candidate: An invalid child candidate.
    @Test(arguments: [order, maximum, "9edf6e545ed1dd23d541099b075fe57cf1fd5fd662fc1f8ce2b5a631a03c998f"])
    func `Child candidates of at least n or summing to zero are refused`(candidate: String) throws {
        #expect(P256Curve().privateKey(candidate: try fixtureBytes(candidate), parent: try fixtureBytes(Self.parent)) == nil)
    }

    /// Verifies that a child key is the candidate plus the parent, modulo n.
    ///
    /// n - 1 gives k - 1; 1 gives k + 1; 0xf0 followed by zeros carries above 2^256 before reducing.
    ///
    /// - Parameters:
    ///   - candidate: A valid child candidate.
    ///   - expected: (candidate + k) mod n.
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
