import Foundation
import Vault

/// Isolated resettable recovery storage used only with published, unfunded recovery fixtures.
actor ResetRecoveryStore: RecoveryStoring {
    private var records: [UUID: Recovery] = [:]
    var count: Int { records.count }

    /// Saves a public fixture under its generated metadata identity.
    /// - Parameters:
    ///   - recovery: The public fixture.
    ///   - recoveryID: Its storage identity.
    func save(_ recovery: Recovery, for recoveryID: UUID) async throws {
        records[recoveryID] = recovery
    }

    /// Loads an isolated fixture without authentication or Keychain access.
    /// - Parameters:
    ///   - recoveryID: The requested identity.
    ///   - reason: The unused authentication explanation.
    /// - Returns: The retained public fixture.
    /// - Throws: A missing-recovery error when the isolated store has no matching record.
    func recovery(for recoveryID: UUID, reason: String) async throws -> Recovery {
        guard let recovery = records[recoveryID] else { throw KeychainStoreError.recoveryUnavailable }
        return recovery
    }

    /// Removes one public fixture.
    /// - Parameter recoveryID: Its storage identity.
    func deleteRecovery(for recoveryID: UUID) async throws {
        records[recoveryID] = nil
    }

    /// Empties this test's recovery without touching any retained wallet.
    func deleteAllRecovery() async throws {
        records.removeAll()
    }
}
