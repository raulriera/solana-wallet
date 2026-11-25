import Foundation
import Testing
import Vault

actor SecurityRecoveryStore: RecoveryStoring {
    private let records: [UUID: Recovery]
    private let readError: (any Error)?
    private(set) var reads: [UUID] = []

    init(records: [UUID: Recovery] = [:], readError: (any Error)? = nil) {
        self.records = records
        self.readError = readError
    }

    func save(_ recovery: Recovery, for recoveryID: UUID) async throws {
        Issue.record("Showing recovery must not save recovery.")
    }

    func recovery(for recoveryID: UUID, reason: String) async throws -> Recovery {
        reads.append(recoveryID)
        if let readError { throw readError }
        guard let recovery = records[recoveryID] else { throw KeychainStoreError.recoveryUnavailable }
        return recovery
    }

    func deleteRecovery(for recoveryID: UUID) async throws {
        Issue.record("Showing recovery must not delete recovery.")
    }

    func deleteAllRecovery() async throws {
        Issue.record("Showing recovery must not delete recovery.")
    }
}
