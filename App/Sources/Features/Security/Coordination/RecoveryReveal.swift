import Foundation
import Vault

/// Reads a wallet's recovery for backup from protected storage.
nonisolated struct RecoveryReveal: RecoveryRevealing {
    private let store: any RecoveryStoring

    /// Creates a recovery reader.
    ///
    /// - Parameter store: The protected recovery storage.
    init(store: any RecoveryStoring) {
        self.store = store
    }

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
