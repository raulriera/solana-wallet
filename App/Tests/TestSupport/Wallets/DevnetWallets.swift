import Foundation
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

/// Your devnet test wallet, derived from the seed in your ignored local configuration.
///
/// Each contributor funds their own seed; tests never create wallets and never save its recovery.
struct DevnetWallets {
    private static let recoveryID = UUID(uuidString: "FDA62506-34AD-426E-8D35-344F45A1B605")!
    private static let senderID = UUID(uuidString: "E2F59EC9-C897-4B39-86A8-84BAE59227AC")!
    private static let recipientID = UUID(uuidString: "9B0AAB8B-85A5-4CB7-91F3-0DB5DFA46B68")!

    /// The recovery both accounts sign with; it describes itself without its words.
    let recovery: Recovery
    /// Account 0, which holds the test funds and pays for each transfer.
    let sender: Account
    /// Account 1, which receives each transfer and returns it.
    let recipient: Account

    /// Derives both accounts from the configured seed, stopping setup when it's missing.
    /// - Returns: The configured devnet wallet's sender and recipient.
    /// - Throws: A test prerequisite failure for a missing or invalid `DEVNET_TEST_SEED`, or a derivation error.
    static func configured() async throws -> DevnetWallets {
        let seed = try #require(ProcessInfo.processInfo.environment["DEVNET_TEST_SEED"],
                                "DEVNET_TEST_SEED must be configured for devnet tests")
        try #require(!seed.isEmpty && !seed.hasPrefix("$("), "DEVNET_TEST_SEED must be configured for devnet tests")
        let recovery = Recovery(phrase: try RecoveryPhrase(seed), passphrase: "")
        return DevnetWallets(recovery: recovery,
                             sender: try await account(senderID, at: .solana, from: recovery),
                             recipient: try await account(recipientID, at: try DerivationPath("m/44'/501'/1'/0'"), from: recovery))
    }

    /// Derives one account from the configured recovery.
    /// - Parameters:
    ///   - id: The account's stable identifier.
    ///   - path: The account's derivation path.
    ///   - recovery: The configured recovery.
    /// - Returns: The account with its derived public address.
    /// - Throws: A derivation or address validation error.
    private static func account(_ id: UUID, at path: DerivationPath, from recovery: Recovery) async throws -> Account {
        let address = try await Wallet().address(for: recovery.phrase, passphrase: recovery.passphrase, path: path)
        return Account(id: id, recoveryID: recoveryID, address: try Address(address), path: path)
    }
}
