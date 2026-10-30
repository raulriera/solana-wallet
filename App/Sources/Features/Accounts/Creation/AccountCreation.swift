import Foundation
import Vault
import Wallet

/// A service that derives new accounts from a saved wallet's recovery.
nonisolated struct AccountCreation: Sendable {
    private let recovery: any RecoveryStoring
    private let wallet: any WalletProviding

    /// Creates an account creation service.
    ///
    /// - Parameters:
    ///   - recovery: The storage that keeps each wallet's recovery.
    ///   - wallet: The service that derives addresses.
    init(recovery: any RecoveryStoring, wallet: any WalletProviding) {
        self.recovery = recovery
        self.wallet = wallet
    }

    /// Reads a wallet's recovery and derives a new account at a path.
    ///
    /// - Parameters:
    ///   - path: The new account's path.
    ///   - recoveryID: The wallet's recovery identifier.
    /// - Returns: The new, unsaved account.
    /// - Throws: `CancellationError`, `KeychainStoreError.recoveryUnavailable`, or a storage or derivation error.
    func account(at path: DerivationPath, inWallet recoveryID: UUID) async throws -> Account {
        let recovery = try await recovery.recovery(for: recoveryID, reason: String(localized: "Add an account to your wallet"))
        let derived = try await wallet.accounts(for: recovery.phrase, passphrase: recovery.passphrase, paths: [path])
        guard let account = derived.first else { throw AccountsError.notAdded }
        return try Account(account, recoveryID: recoveryID)
    }
}
