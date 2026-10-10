import Foundation
import Vault

/// Reads recovery for backup through protected storage, which owns authentication.
nonisolated struct RecoveryReveal: RecoveryRevealing {
    private let store: any RecoveryStoring

    /// Connects backup display to the app's protected recovery storage.
    /// - Parameter store: The storage that authenticates each read.
    init(store: any RecoveryStoring) {
        self.store = store
    }

    /// Reads the wallet's shared recovery and pairs it with the wallet's own account path.
    /// - Parameter account: The window's wallet.
    /// - Returns: The backup, or ``RecoveryDisplay/unavailable`` when this device no longer has the recovery.
    /// - Throws: `CancellationError` if the user cancels authentication, or another storage error.
    func display(for account: Account) async throws -> RecoveryDisplay {
        do {
            let recovery = try await store.recovery(for: account.recoveryID,
                                                    reason: String(localized: "Show your recovery phrase"))
            return .backup(RecoveryBackup(phrase: recovery.phrase, passphrase: recovery.passphrase, path: account.path))
        } catch KeychainStoreError.recoveryUnavailable {
            return .unavailable
        }
    }
}
