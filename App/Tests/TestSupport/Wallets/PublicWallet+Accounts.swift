import Foundation
import Testing
import Vault
import Wallet
@testable import widgets

extension PublicWallet {
    /// The published recovery that public-fixture accounts come from.
    /// - Returns: The public test phrase without a BIP-39 passphrase.
    /// - Throws: A validation error, which doesn't happen.
    static func recovery() throws -> Recovery {
        Recovery(phrase: try RecoveryPhrase(words), passphrase: "")
    }

    /// Derives a public-fixture account at `m/44'/501'/i'/0'`.
    /// - Parameters:
    ///   - index: The account index i.
    ///   - recoveryID: The wallet's recovery identifier.
    /// - Returns: The account with its derived address and a new identity.
    /// - Throws: A derivation or test prerequisite error.
    static func account(index: UInt32 = 0, recoveryID: UUID) async throws -> widgets.Account {
        let recovery = try recovery()
        let derived = try #require(try await Wallet().accounts(for: recovery.phrase, passphrase: recovery.passphrase,
                                                               paths: [.solana(account: index)]).first)
        return try widgets.Account(derived, recoveryID: recoveryID)
    }
}
