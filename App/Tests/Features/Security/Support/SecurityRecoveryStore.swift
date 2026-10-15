import Foundation
import Testing
import Vault

/// Read-only public-fixture recovery storage with a controllable read failure.
actor SecurityRecoveryStore: RecoveryStoring {
    private let records: [UUID: Recovery]
    private let readError: (any Error)?
    private(set) var reads: [UUID] = []

    /// Configures saved fixtures and an optional failure for every read.
    /// - Parameters:
    ///   - records: Public test recovery by recovery identity.
    ///   - readError: The error every read throws, such as a cancelled prompt.
    init(records: [UUID: Recovery] = [:], readError: (any Error)? = nil) {
        self.records = records
        self.readError = readError
    }

    /// Reports any write, because showing recovery must not change storage.
    /// - Parameters:
    ///   - recovery: The recovery the caller tried to save.
    ///   - recoveryID: The identity the caller tried to save under.
    func save(_ recovery: Recovery, for recoveryID: UUID) async throws {
        Issue.record("Showing recovery must not save recovery.")
    }

    /// Returns a saved fixture while recording each read.
    /// - Parameters:
    ///   - recoveryID: The recovery identity to read.
    ///   - reason: The caller's authentication explanation.
    /// - Returns: The saved fixture.
    /// - Throws: The configured failure, or a missing-recovery error when no record exists.
    func recovery(for recoveryID: UUID, reason: String) async throws -> Recovery {
        reads.append(recoveryID)
        if let readError { throw readError }
        guard let recovery = records[recoveryID] else { throw KeychainStoreError.recoveryUnavailable }
        return recovery
    }

    /// Reports any deletion, because showing recovery must not change storage.
    /// - Parameter recoveryID: The identity the caller tried to delete.
    func deleteRecovery(for recoveryID: UUID) async throws {
        Issue.record("Showing recovery must not delete recovery.")
    }

    /// Reports any deletion, because showing recovery must not change storage.
    func deleteAllRecovery() async throws {
        Issue.record("Showing recovery must not delete recovery.")
    }
}
