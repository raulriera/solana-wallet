import Testing
@testable import Wallet

struct DerivationPathPrivateBalanceTests {
    @Test(arguments: [
        ("m/44'/501'/0'/0'", 0), ("m/44'/501'/1'/0'", 1), ("m/44'/501'/2147483647'/0'", 2_147_483_647),
        ("m", nil), ("m/44'/501'/0'", nil), ("m/44'/501'/0'/1'", nil), ("m/44'/60'/0'/0'", nil),
        ("m/44'/501'/0'/0'/0'", nil), ("m/45'/501'/0'/0'", nil),
    ] as [(String, UInt32?)])
    func `Only Solana account paths give an account index and have private-balance keys`(
        path: String,
        account: UInt32?
    ) throws {
        let derivationPath = try DerivationPath(path)

        #expect(derivationPath.privateBalanceAccount == account)
        #expect(derivationPath.hasPrivateBalanceKeys == (account != nil))
    }
}
