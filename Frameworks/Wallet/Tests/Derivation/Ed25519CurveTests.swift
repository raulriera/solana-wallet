import Testing
@testable import Wallet

/// Verifies SLIP-0010's Ed25519 candidate rule directly.
struct Ed25519CurveTests {
    /// Verifies that every candidate is the private key, for the master key and for a child.
    ///
    /// All-zero and all-0xff candidates are the extremes; the last candidate is SLIP-0010's first
    /// Ed25519 master key. SLIP-0010 never hashes again for Ed25519.
    ///
    /// - Parameters:
    ///   - candidate: A 32-byte I_L.
    ///   - parent: No parent for the master key, or a parent's private key.
    @Test(arguments: [
        "0000000000000000000000000000000000000000000000000000000000000000",
        "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "2b4be7f19ee27bbf30c667b642d5f4aa69fd169872f8fc3059c08ebae2eb19e7",
    ], [
        nil,
        "68e0fe46dfb67e368c75379acec591dad19df3cde26e63b93a8e704f1dade7a3",
    ])
    func `Every candidate is accepted unchanged`(candidate: String, parent: String?) throws {
        let bytes = try fixtureBytes(candidate)

        #expect(Ed25519Curve().privateKey(candidate: bytes, parent: try parent.map(fixtureBytes)) == bytes)
    }
}
