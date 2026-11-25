import Foundation
import Testing
import Vault
import Wallet
@testable import widgets

extension ThrowawayWallet {
    static func recovery(passphrase: String = "") throws -> Recovery {
        Recovery(phrase: try RecoveryPhrase(words), passphrase: passphrase)
    }

    static func account(index: UInt32 = 0, recoveryID: UUID) async throws -> widgets.Account {
        let recovery = try recovery()
        let derived = try #require(try await Wallet().accounts(for: recovery.phrase, passphrase: recovery.passphrase,
                                                               paths: [.solana(account: index)]).first)
        return try widgets.Account(derived, recoveryID: recoveryID)
    }
}
