import Testing
@testable import Wallet

struct DerivationTests {
    private static let firstSeed = "000102030405060708090a0b0c0d0e0f"

    private static let secondSeed = "fffcf9f6f3f0edeae7e4e1dedbd8d5d2cfccc9c6c3c0bdbab7b4b1aeaba8a5a2"
        + "9f9c999693908d8a8784817e7b7875726f6c696663605d5a5754514e4b484542"

    @Test(arguments: [
        (firstSeed, "m", "2b4be7f19ee27bbf30c667b642d5f4aa69fd169872f8fc3059c08ebae2eb19e7",
         "90046a93de5380a72b5e45010748567d5ea02bbf6522f979e05c0d8d8ca9fffb"),
        (secondSeed, "m/0'", "1559eb2bbec5790b0c65d8693e4d0875b1747f4970ae8b650486ed7470845635",
         "0b78a3226f915c082bf118f83618a618ab6dec793752624cbeb622acb562862d"),
        (secondSeed, "m/0'/2147483647'", "ea4f5bfe8694d8bb74b7b59404632fd5968b774ed545e810de9c32a4fb4192f4",
         "138f0b2551bcafeca6ff2aa88ba8ed0ed8de070841f0c4ef0165df8181eaad7f"),
        (firstSeed, "m/0'/1'/2'", "92a5b23c0b8a99e37d07df3fb9966917f5d06e02ddbd909c7e184371463e9fc9",
         "2e69929e00b5ab250f49c3fb1c12f252de4fed2c1db88387094a0f8c4c9ccd6c"),
        (secondSeed, "m/0'/2147483647'/1'/2147483646'", "5837736c89570de861ebc173b1086da4f505d4adb387c6a1b1342d5e4ac9ec72",
         "0902fe8a29f9140480a00ef244bd183e8a13288e4412d8389d140aac1794825a"),
        (firstSeed, "m/0'/1'/2'/2'/1000000000'", "8f94d394a8e8fd6b1bc2f3f49f5c47e385281d5c17e65324b0f62483e37e8793",
         "68789923a0cac2cd5a29172a475fe9e0fb14cd6adb5ad98a3fa70333e7afa230"),
    ])
    func `Hardened paths derive the SLIP-0010 Ed25519 reference nodes`(seed: String, path: String, key: String, chainCode: String) throws {
        let node = try KeyDerivation.node(seed: fixtureBytes(seed), path: DerivationPath(path))

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

    @Test(arguments: ["m", "m/44'/501'", "m/44'/501'/0'/1'", "m/44'/60'/0'/0'", "m/44'/501'/0'/0'/0'", "m/45'/501'/0'"])
    func `Other paths have no account index`(path: String) throws {
        #expect(try DerivationPath(path).accountIndex == nil)
    }
}
