import CryptoKit
import Testing
@testable import Wallet

/// Tests the standard seed and private key derivation independently of address formatting.
struct DerivationTests {
    /// The seed of SLIP-0010's first test vectors and its nist256p1 derivation retry vector.
    private static let firstSeed = "000102030405060708090a0b0c0d0e0f"

    /// The seed of SLIP-0010's second test vectors.
    private static let secondSeed = "fffcf9f6f3f0edeae7e4e1dedbd8d5d2cfccc9c6c3c0bdbab7b4b1aeaba8a5a2"
        + "9f9c999693908d8a8784817e7b7875726f6c696663605d5a5754514e4b484542"

    /// The seed of SLIP-0010's nist256p1 seed retry vector, whose first master candidate is refused.
    private static let retrySeed = "a7305bc8df8d0951f0cb224c0e95d7707cbdf2c6ce7e8d481fec69c7ff5e9446"

    /// Verifies PBKDF2 against published seeds, including every supported phrase length.
    ///
    /// - Parameter vector: A public BIP-39 example using the passphrase `TREZOR`.
    @Test(arguments: try BIP39Vector.examples())
    func `Recovery phrases derive the BIP-39 reference seeds`(vector: BIP39Vector) throws {
        let phrase = try RecoveryPhrase(vector.phrase)
        let seed = try SeedDerivation.seed(for: phrase, passphrase: "TREZOR")

        #expect(seed == (try fixtureBytes(vector.seed)))
    }

    /// Verifies master and hardened child nodes against SLIP-0010's two Ed25519 vectors.
    ///
    /// - Parameters:
    ///   - seed: The vector's seed.
    ///   - path: A path from the published vector.
    ///   - key: The independently specified private key seed.
    ///   - chainCode: The independently specified chain code.
    @Test(arguments: [
        (firstSeed, "m", "2b4be7f19ee27bbf30c667b642d5f4aa69fd169872f8fc3059c08ebae2eb19e7",
         "90046a93de5380a72b5e45010748567d5ea02bbf6522f979e05c0d8d8ca9fffb"),
        (firstSeed, "m/0'", "68e0fe46dfb67e368c75379acec591dad19df3cde26e63b93a8e704f1dade7a3",
         "8b59aa11380b624e81507a27fedda59fea6d0b779a778918a2fd3590e16e9c69"),
        (firstSeed, "m/0'/1'", "b1d0bad404bf35da785a64ca1ac54b2617211d2777696fbffaf208f746ae84f2",
         "a320425f77d1b5c2505a6b1b27382b37368ee640e3557c315416801243552f14"),
        (firstSeed, "m/0'/1'/2'", "92a5b23c0b8a99e37d07df3fb9966917f5d06e02ddbd909c7e184371463e9fc9",
         "2e69929e00b5ab250f49c3fb1c12f252de4fed2c1db88387094a0f8c4c9ccd6c"),
        (firstSeed, "m/0'/1'/2'/2'", "30d1dc7e5fc04c31219ab25a27ae00b50f6fd66622f6e9c913253d6511d1e662",
         "8f6d87f93d750e0efccda017d662a1b31a266e4a6f5993b15f5c1f07f74dd5cc"),
        (firstSeed, "m/0'/1'/2'/2'/1000000000'", "8f94d394a8e8fd6b1bc2f3f49f5c47e385281d5c17e65324b0f62483e37e8793",
         "68789923a0cac2cd5a29172a475fe9e0fb14cd6adb5ad98a3fa70333e7afa230"),
        (secondSeed, "m", "171cb88b1b3c1db25add599712e36245d75bc65a1a5c9e18d76f9f2b1eab4012",
         "ef70a74db9c3a5af931b5fe73ed8e1a53464133654fd55e7a66f8570b8e33c3b"),
        (secondSeed, "m/0'", "1559eb2bbec5790b0c65d8693e4d0875b1747f4970ae8b650486ed7470845635",
         "0b78a3226f915c082bf118f83618a618ab6dec793752624cbeb622acb562862d"),
        (secondSeed, "m/0'/2147483647'", "ea4f5bfe8694d8bb74b7b59404632fd5968b774ed545e810de9c32a4fb4192f4",
         "138f0b2551bcafeca6ff2aa88ba8ed0ed8de070841f0c4ef0165df8181eaad7f"),
        (secondSeed, "m/0'/2147483647'/1'", "3757c7577170179c7868353ada796c839135b3d30554bbb74a4b1e4a5a58505c",
         "73bd9fff1cfbde33a1b846c27085f711c0fe2d66fd32e139d3ebc28e5a4a6b90"),
        (secondSeed, "m/0'/2147483647'/1'/2147483646'", "5837736c89570de861ebc173b1086da4f505d4adb387c6a1b1342d5e4ac9ec72",
         "0902fe8a29f9140480a00ef244bd183e8a13288e4412d8389d140aac1794825a"),
        (secondSeed, "m/0'/2147483647'/1'/2147483646'/2'", "551d333177df541ad876a60ea71f00447931c0a9da16f227c11ea080d7391b8d",
         "5d70af781f3a37b829f0d060924d5e960bdc02e85423494afc0b1a41bbe196d4"),
    ])
    func `Hardened paths derive the SLIP-0010 Ed25519 reference nodes`(seed: String, path: String, key: String, chainCode: String) throws {
        let node = try KeyDerivation.node(seed: fixtureBytes(seed), path: DerivationPath(path), curve: .ed25519)

        #expect(node.key == (try fixtureBytes(key)))
        #expect(node.chainCode == (try fixtureBytes(chainCode)))
    }

    /// Verifies nist256p1 master and hardened child nodes, including master and child retries.
    ///
    /// The first five vectors are SLIP-0010's: test vector 1 at `m` and `m/0'`, test vector 2 at
    /// `m`, the hardened parent `m/28578'` of the derivation retry vector, and the seed retry at
    /// `m`. `m/28578'` doesn't retry; the published retry is at a non-hardened child, which this
    /// derivation doesn't support. The last three are real hardened-child retries, where I_L ≥ n,
    /// found by an independent search in C and derived independently with Python's `hmac` and
    /// `hashlib` and pure-Python P-256 arithmetic. At `m/1363273311'` and `m/1992219942'`, the
    /// master key and the child each retry once; at `m/1'/655108711'`, the second child retries once.
    ///
    /// - Parameters:
    ///   - seed: The vector's seed.
    ///   - path: The vector's hardened path.
    ///   - key: The expected big-endian private scalar.
    ///   - chainCode: The expected chain code.
    ///   - publicKey: The expected compressed public key.
    @Test(arguments: [
        (firstSeed, "m", "612091aaa12e22dd2abef664f8a01a82cae99ad7441b7ef8110424915c268bc2",
         "beeb672fe4621673f722f38529c07392fecaa61015c80c34f29ce8b41b3cb6ea",
         "0266874dc6ade47b3ecd096745ca09bcd29638dd52c2c12117b11ed3e458cfa9e8"),
        (firstSeed, "m/0'", "6939694369114c67917a182c59ddb8cafc3004e63ca5d3b84403ba8613debc0c",
         "3460cea53e6a6bb5fb391eeef3237ffd8724bf0a40e94943c98b83825342ee11",
         "0384610f5ecffe8fda089363a41f56a5c7ffc1d81b59a612d0d649b2d22355590c"),
        (secondSeed, "m", "eaa31c2e46ca2962227cf21d73a7ef0ce8b31c756897521eb6c7b39796633357",
         "96cd4465a9644e31528eda3592aa35eb39a9527769ce1855beafc1b81055e75d",
         "02c9e16154474b3ed5b38218bb0463e008f89ee03e62d22fdcc8014beab25b48fa"),
        (firstSeed, "m/28578'", "06f0db126f023755d0b8d86d4591718a5210dd8d024e3e14b6159d63f53aa669",
         "e94c8ebe30c2250a14713212f6449b20f3329105ea15b652ca5bdfc68f6c65c2",
         "02519b5554a4872e8c9c1c847115363051ec43e93400e030ba3c36b52a3e70a5b7"),
        (retrySeed, "m", "3b8c18469a4634517d6d0b65448f8e6c62091b45540a1743c5846be55d47d88f",
         "7762f9729fed06121fd13f326884c82f59aa95c57ac492ce8c9654e60efd130c",
         "0383619fadcde31063d8c5cb00dbfe1713f3e6fa169d8541a798752a1c1ca0cb20"),
        (retrySeed, "m/1363273311'", "0213ada6e9dc77c431aa37826dfdc7231983a04a8e5310bc0ec965adbe1215bd",
         "356dd432d445974e229d1a9799701821dbd4931f50302beb00c5512cd561a355",
         "03142eafd1b2c965025fa416fa99984a8086a669f0124b60a27891e7cde5392471"),
        (retrySeed, "m/1992219942'", "4752608fc7c55be36d2092cefde95020f06c82c9a85a64ba3d3e8e731ddaa1f7",
         "aee30cbfbea633f932bd8b5015401528735fccf3996e0813dff012edd227d4e1",
         "03f07907effffbb8f513922d654882af4a19f715900445c97aca15b151ca12b2f3"),
        (firstSeed, "m/1'/655108711'", "ebd6a51b83d71322d022f3c189a07be80099b5c2f991dd1e2956f9690860e571",
         "db4ecd277fcbe68d4bb76d215d383745c22f91ff9a8cdf39dd2f0bd3aebba484",
         "032c9b94222509ea040ac763578bb903c5b2e5bd60fc518941b6f54fd85f90ca9c"),
    ])
    func `Hardened paths derive the nist256p1 reference nodes`(
        seed: String, path: String, key: String, chainCode: String, publicKey: String
    ) throws {
        let node = try KeyDerivation.node(seed: fixtureBytes(seed), path: DerivationPath(path), curve: .p256)
        let privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: node.key)

        #expect(node.key == (try fixtureBytes(key)))
        #expect(node.chainCode == (try fixtureBytes(chainCode)))
        #expect(Array(privateKey.publicKey.compressedRepresentation) == (try fixtureBytes(publicKey)))
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

    /// Verifies that both Solana account families give their account index.
    ///
    /// - Parameters:
    ///   - path: A path `m/44'/501'/i'/0'` or `m/44'/501'/i'`.
    ///   - index: The path's account index i.
    @Test(arguments: [
        ("m/44'/501'/0'/0'", 0), ("m/44'/501'/1'", 1), ("m/44'/501'/2147483647'/0'", 2_147_483_647),
    ])
    func `Solana account paths give their account index`(path: String, index: UInt32) throws {
        #expect(try DerivationPath(path).accountIndex == index)
    }

    /// Verifies that an account in the default Solana family has the path that parsing gives.
    ///
    /// - Parameter index: The account index i.
    @Test(arguments: [0, 1, 2_147_483_647] as [UInt32])
    func `Default Solana accounts have their path`(index: UInt32) throws {
        let path = DerivationPath.solana(account: index)

        #expect(path == (try DerivationPath("m/44'/501'/\(index)'/0'")))
        #expect(path.accountIndex == index)
    }

    /// Verifies that the first default Solana account is the default path.
    @Test
    func `The first default Solana account is the default path`() {
        #expect(DerivationPath.solana(account: 0) == .solana)
    }

    /// Verifies that paths outside both Solana account families have no account index.
    ///
    /// - Parameter path: Another hardened path.
    @Test(arguments: ["m", "m/44'/501'", "m/44'/501'/0'/1'", "m/44'/60'/0'/0'", "m/44'/501'/0'/0'/0'", "m/45'/501'/0'"])
    func `Other paths have no account index`(path: String) throws {
        #expect(try DerivationPath(path).accountIndex == nil)
    }
}
