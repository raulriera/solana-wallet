import Foundation
import Testing
import Wallet
@testable import widgets

/// Verifies how an account is named.
struct AccountTests {
    /// Accounts in both Solana families are numbered from 1 by their account index, as Phantom names them.
    /// - Parameters:
    ///   - path: The account's path.
    ///   - name: The name Phantom would show.
    @Test(arguments: [("m/44'/501'/0'/0'", "Account 1"), ("m/44'/501'/1'", "Account 2"), ("m/44'/501'/9'/0'", "Account 10")])
    func `Solana accounts are numbered from one`(path: String, name: String) throws {
        let account = try widgets.Account.fixture(index: 0)

        let named = widgets.Account(id: account.id, recoveryID: account.recoveryID, address: account.address,
                                    path: try DerivationPath(path))

        #expect(named.name == name)
    }

    /// An account outside the Solana families has no number, so its path names it.
    @Test
    func `Other accounts are named by their path`() throws {
        let account = try widgets.Account.fixture(index: 0)

        let named = widgets.Account(id: account.id, recoveryID: account.recoveryID, address: account.address,
                                    path: try DerivationPath("m/44'/60'/0'/0'"))

        #expect(named.name == "m/44'/60'/0'/0'")
    }

    /// A name the person gave the account replaces its numbered name, which stays its default.
    @Test
    func `A custom name replaces the numbered name`() throws {
        var account = try widgets.Account.fixture(index: 1)

        account.customName = "Savings"

        #expect(account.name == "Savings")
        #expect(account.defaultName == "Account 2")
    }
}
