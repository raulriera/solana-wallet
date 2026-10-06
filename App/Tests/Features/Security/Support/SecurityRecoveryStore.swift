import Foundation
import Testing
import Vault

/// Read-only public-fixture recovery storage with a controllable read failure.
actor SecurityRecoveryStore: RecoveryStoring {
    private let records: [UUID: Recovery]
    private let readFailure: (any Error)?
    private(set) var reads: [UUID] = []

    /// Configures saved fixtures and an optional failure for every read.
    /// - Parameters:
    ///   - records: Public test recovery by recovery identity.
    ///   - readFailure: The error every read throws, such as a cancelled prompt.
    init(records: [UUID: Recovery] = [:], readFailure: (any Error)? = nil) {
        self.records = records
        self.readFailure = readFailure
    }

    /// Reports any write, because showing recovery must not change storage.
    /// - Parameters:
    ///   - recovery: The recovery the caller tried to save.
    ///   - walletID: The identity the caller tried to save under.
    func save(_ recovery: Recovery, for walletID: UUID) async throws {
        Issue.record("Showing recovery must not save recovery.")
    }

    /// Returns a saved fixture while recording each read.
    /// - Parameters:
    ///   - walletID: The recovery identity to read.
    ///   - reason: The caller's authentication explanation.
    /// - Returns: The saved fixture.
    /// - Throws: The configured failure, or a missing-recovery error when no record exists.
    func recovery(for walletID: UUID, reason: String) async throws -> Recovery {
        reads.append(walletID)
        if let readFailure { throw readFailure }
        guard let recovery = records[walletID] else { throw KeychainStore.Failure.recoveryUnavailable }
        return recovery
    }

    /// Reports any deletion, because showing recovery must not change storage.
    /// - Parameter walletID: The identity the caller tried to delete.
    func deleteRecovery(for walletID: UUID) async throws {
        Issue.record("Showing recovery must not delete recovery.")
    }
}
