import Testing
@testable import Wallet

/// Tests the standard seed and private key derivation independently of address formatting.
struct DerivationTests {
    /// Verifies PBKDF2 against published seeds, including every supported phrase length.
    ///
    /// - Parameter vector: A public BIP-39 example using the passphrase `TREZOR`.
    @Test(arguments: try BIP39Vector.examples())
    func `Recovery phrases derive the BIP-39 reference seeds`(vector: BIP39Vector) throws {
        let phrase = try RecoveryPhrase(vector.phrase)
        let seed = try SeedDerivation.seed(for: phrase, passphrase: "TREZOR")

        #expect(seed == (try fixtureBytes(vector.seed)))
    }

    /// Verifies master and hardened child keys against SLIP-0010's first Ed25519 vector.
    ///
    /// - Parameters:
    ///   - path: A path from the published vector.
    ///   - expected: The independently specified private key seed.
    @Test(arguments: [
        ("m", "2b4be7f19ee27bbf30c667b642d5f4aa69fd169872f8fc3059c08ebae2eb19e7"),
        ("m/0'", "68e0fe46dfb67e368c75379acec591dad19df3cde26e63b93a8e704f1dade7a3"),
        ("m/0'/1'", "b1d0bad404bf35da785a64ca1ac54b2617211d2777696fbffaf208f746ae84f2"),
        ("m/0'/1'/2'", "92a5b23c0b8a99e37d07df3fb9966917f5d06e02ddbd909c7e184371463e9fc9"),
        ("m/0'/1'/2'/2'", "30d1dc7e5fc04c31219ab25a27ae00b50f6fd66622f6e9c913253d6511d1e662"),
        ("m/0'/1'/2'/2'/1000000000'", "8f94d394a8e8fd6b1bc2f3f49f5c47e385281d5c17e65324b0f62483e37e8793"),
    ])
    func `Hardened paths derive the SLIP-0010 reference keys`(path: String, expected: String) throws {
        let seed = try fixtureBytes("000102030405060708090a0b0c0d0e0f")
        let key = try KeyDerivation.privateKey(seed: seed, path: DerivationPath(path))

        #expect(key == (try fixtureBytes(expected)))
    }

    /// Verifies rejection of malformed paths, non-hardened indices, and integer overflow.
    ///
    /// - Parameter path: An invalid derivation path.
    @Test(arguments: [
        "", "M/44'", "m/", "m//0'", "m/0", "m/-1'", "m/+1'", "m/2147483648'", "m/4294967296'",
    ])
    func `Derivation paths reject malformed or non-hardened indices`(path: String) {
        #expect(throws: DerivationPath.ValidationError.invalidPath) { try DerivationPath(path) }
    }
}
