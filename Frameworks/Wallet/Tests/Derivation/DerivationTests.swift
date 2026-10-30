import Testing
@testable import Wallet

struct DerivationTests {
    private static let firstSeed = "000102030405060708090a0b0c0d0e0f"

    private static let secondSeed = "fffcf9f6f3f0edeae7e4e1dedbd8d5d2cfccc9c6c3c0bdbab7b4b1aeaba8a5a2"
        + "9f9c999693908d8a8784817e7b7875726f6c696663605d5a5754514e4b484542"

    @Test(arguments: try BIP39Vector.examples())
    func `Recovery phrases derive the BIP-39 reference seeds`(vector: BIP39Vector) throws {
        let phrase = try RecoveryPhrase(vector.phrase)
        let seed = try SeedDerivation.seed(for: phrase, passphrase: "TREZOR")

        #expect(seed == (try fixtureBytes(vector.seed)))
    }

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

    @Test(arguments: [
        "", "M/44'", "m/", "m//0'", "m/0", "m/-1'", "m/+1'", "m/2147483648'", "m/4294967296'",
    ])
    func `Derivation paths reject malformed or non-hardened indices`(path: String) {
        #expect(throws: DerivationPath.ValidationError.invalidPath) { try DerivationPath(path) }
    }

    @Test(arguments: [
        ("m/44'/501'/0'/0'", 0), ("m/44'/501'/1'", 1), ("m/44'/501'/2147483647'/0'", 2_147_483_647),
    ])
    func `Solana account paths give their account index`(path: String, index: UInt32) throws {
        #expect(try DerivationPath(path).accountIndex == index)
    }

    @Test(arguments: [0, 1, 2_147_483_647] as [UInt32])
    func `Default Solana accounts have their path`(index: UInt32) throws {
        let path = DerivationPath.solana(account: index)

        #expect(path == (try DerivationPath("m/44'/501'/\(index)'/0'")))
        #expect(path.accountIndex == index)
    }

    @Test
    func `The first default Solana account is the default path`() {
        #expect(DerivationPath.solana(account: 0) == .solana)
    }

    @Test(arguments: ["m", "m/44'/501'", "m/44'/501'/0'/1'", "m/44'/60'/0'/0'", "m/44'/501'/0'/0'/0'", "m/45'/501'/0'"])
    func `Other paths have no account index`(path: String) throws {
        #expect(try DerivationPath(path).accountIndex == nil)
    }
}
