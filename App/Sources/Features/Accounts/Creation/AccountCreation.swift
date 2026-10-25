import Foundation
import Vault
import Wallet

/// Creates a new account in a saved wallet from the wallet's recovery, which protected storage reads only after the
/// person authenticates; nothing is saved.
nonisolated struct AccountCreation: Sendable {
    private let recovery: any RecoveryStoring
    private let wallet: any WalletProviding

    /// Connects account creation to protected recovery and local derivation.
    /// - Parameters:
    ///   - recovery: The storage that authenticates each read of a wallet's recovery.
    ///   - wallet: Local address derivation.
    init(recovery: any RecoveryStoring, wallet: any WalletProviding) {
        self.recovery = recovery
        self.wallet = wallet
    }

    /// Reads a wallet's recovery and derives a new account at a path.
    /// - Parameters:
    ///   - path: The new account's path.
    ///   - recoveryID: The wallet's recovery identifier.
    /// - Returns: The new account, with a new identity and no name of its own, which isn't saved yet.
    /// - Throws: `CancellationError` if the person cancels authentication,
    ///   `KeychainStoreError.recoveryUnavailable` when this device no longer has the recovery, or another storage or
    ///   derivation error.
    func account(at path: DerivationPath, inWallet recoveryID: UUID) async throws -> Account {
        let recovery = try await recovery.recovery(for: recoveryID, reason: String(localized: "Add an account to your wallet"))
        let derived = try await wallet.accounts(for: recovery.phrase, passphrase: recovery.passphrase, paths: [path])
        // Derivation gives one account for each path.
        guard let account = derived.first else { throw AccountsError.notAdded }
        return try Account(account, recoveryID: recoveryID)
    }
}
