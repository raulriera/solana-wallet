import Foundation
import Transactions
import Vault
import Wallet

/// Reusable devnet-only test accounts whose recovery remains in the device's protected Vault.
enum DevnetWallets {
    static let store: any RecoveryStoring = KeychainStore(service: "widgetsTests.devnet.recovery")
    static let senderID = UUID(uuidString: "E2F59EC9-C897-4B39-86A8-84BAE59227AC")!
    static let recipientID = UUID(uuidString: "9B0AAB8B-85A5-4CB7-91F3-0DB5DFA46B68")!

    /// Retrieves a retained test account, creating it only before it has a recorded address.
    ///
    /// A missing or invalidated Keychain item with recorded funding identity fails
    /// setup instead of silently replacing the wallet. Only public addresses are
    /// stored in preferences; recovery material never enters configuration or logs.
    ///
    /// - Parameter id: One of the stable devnet test wallet identifiers.
    /// - Returns: The derived public address after saving and rereading its recovery.
    /// - Throws: A storage, derivation, cancellation, or identity mismatch error.
    static func address(for id: UUID) async throws -> Address {
        let key = "widgetsTests.devnet.address.\(id.uuidString)"
        let recorded = UserDefaults.standard.string(forKey: key)
        var expected = recorded
        let recovery: Recovery
        do {
            recovery = try await store.recovery(for: id, reason: "Unlock reusable devnet test wallet")
        } catch KeychainStore.Failure.recoveryUnavailable {
            guard recorded == nil else { throw KeychainStore.Failure.recoveryUnavailable }
            let created = Recovery(phrase: try Wallet().recoveryPhrase(), passphrase: "")
            expected = try await Wallet().address(for: created.phrase, passphrase: created.passphrase, path: .solana)
            try await store.save(created, for: id)
            recovery = try await store.recovery(for: id, reason: "Verify saved devnet test wallet")
        }
        let address = try await Wallet().address(for: recovery.phrase, passphrase: recovery.passphrase, path: .solana)
        guard expected == nil || expected == address else { throw Failure.identityChanged }
        UserDefaults.standard.set(address, forKey: key)
        return try Address(address)
    }

    /// A retained public identity doesn't agree with the protected wallet.
    private enum Failure: Error { case identityChanged }
}
