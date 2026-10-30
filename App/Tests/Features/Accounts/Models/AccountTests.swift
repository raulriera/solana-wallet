import Foundation
import Testing
import Wallet
@testable import widgets

struct AccountTests {
    @Test(arguments: [("m/44'/501'/0'/0'", "Account 1"), ("m/44'/501'/1'", "Account 2"), ("m/44'/501'/9'/0'", "Account 10")])
    func `Solana accounts are numbered from one`(path: String, name: String) throws {
        let account = try widgets.Account.fixture(index: 0)

        let named = widgets.Account(id: account.id, recoveryID: account.recoveryID, address: account.address,
                                    path: try DerivationPath(path))

        #expect(named.name == name)
    }

    @Test
    func `Other accounts are named by their path`() throws {
        let account = try widgets.Account.fixture(index: 0)

        let named = widgets.Account(id: account.id, recoveryID: account.recoveryID, address: account.address,
                                    path: try DerivationPath("m/44'/60'/0'/0'"))

        #expect(named.name == "m/44'/60'/0'/0'")
    }

    @Test
    func `A custom name replaces the numbered name`() throws {
        var account = try widgets.Account.fixture(index: 1)

        account.customName = "Savings"

        #expect(account.name == "Savings")
        #expect(account.defaultName == "Account 2")
    }
}
