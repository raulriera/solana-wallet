import Foundation
import Testing
import Vault

actor SigningRecoveryStore: RecoveryStoring {
    private let stored: Recovery
    private let error: (any Error)?
    private let gate: Suspension?
    private(set) var reads: [(recoveryID: UUID, reason: String)] = []

    init(recovery: Recovery, error: (any Error)? = nil, gate: Suspension? = nil) {
        stored = recovery
        self.error = error
        self.gate = gate
    }

    func recovery(for recoveryID: UUID, reason: String) async throws -> Recovery {
        reads.append((recoveryID, reason))
        if let error { throw error }
        if let gate { await gate.suspend() }
        return stored
    }

    func save(_ recovery: Recovery, for recoveryID: UUID) async throws {
        Issue.record("Signing must not save recovery material.")
    }

    func deleteRecovery(for recoveryID: UUID) async throws {
        Issue.record("Signing must not delete recovery material.")
    }

    func deleteAllRecovery() async throws {
        Issue.record("Signing must not delete recovery material.")
    }
}
