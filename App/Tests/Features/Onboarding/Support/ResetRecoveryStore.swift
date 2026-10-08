import Foundation
import Vault

/// Isolated resettable recovery storage used only with published, unfunded recovery fixtures.
actor ResetRecoveryStore: RecoveryStoring {
    private var records: [UUID: Recovery] = [:]
    var count: Int { records.count }

    /// Saves a public fixture under its generated metadata identity.
    /// - Parameters:
    ///   - recovery: The public fixture.
    ///   - walletID: Its storage identity.
    func save(_ recovery: Recovery, for walletID: UUID) async throws {
        records[walletID] = recovery
    }

    /// Loads an isolated fixture without authentication or Keychain access.
    /// - Parameters:
    ///   - walletID: The requested identity.
    ///   - reason: The unused authentication explanation.
    /// - Returns: The retained public fixture.
    /// - Throws: A missing-recovery error when the isolated store has no matching record.
    func recovery(for walletID: UUID, reason: String) async throws -> Recovery {
        guard let recovery = records[walletID] else { throw KeychainStore.Failure.recoveryUnavailable }
        return recovery
    }

    /// Removes one public fixture.
    /// - Parameter walletID: Its storage identity.
    func deleteRecovery(for walletID: UUID) async throws {
        records[walletID] = nil
    }

    /// Empties this test's recovery without touching any retained wallet.
    func deleteAllRecovery() async throws {
        records.removeAll()
    }
}
