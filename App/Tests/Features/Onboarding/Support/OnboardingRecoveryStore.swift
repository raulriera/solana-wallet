import Foundation
import Testing
import Vault

actor OnboardingRecoveryStore: RecoveryStoring {
    private var records: [UUID: Recovery] = [:]
    private let firstError: (any Error)?
    private let commitBeforeError: Bool
    private let replacement: Recovery?
    private let gate: Suspension?
    private(set) var saves: [UUID] = []
    private(set) var reads: [UUID] = []
    private(set) var deletions: [UUID] = []

    init(firstError: (any Error)? = nil, commitBeforeError: Bool = false,
         replacement: Recovery? = nil, gate: Suspension? = nil) {
        self.firstError = firstError
        self.commitBeforeError = commitBeforeError
        self.replacement = replacement
        self.gate = gate
    }

    func save(_ recovery: Recovery, for recoveryID: UUID) async throws {
        saves.append(recoveryID)
        guard records[recoveryID] == nil else { throw KeychainStoreError.duplicateRecovery }
        let error = saves.count == 1 ? firstError : nil
        if error == nil || commitBeforeError { records[recoveryID] = replacement ?? recovery }
        if saves.count == 1, let gate { await gate.suspend() }
        if let error { throw error }
    }

    func recovery(for recoveryID: UUID, reason: String) async throws -> Recovery {
        reads.append(recoveryID)
        guard let recovery = records[recoveryID] else { throw KeychainStoreError.recoveryUnavailable }
        return recovery
    }

    func contains(_ id: UUID) -> Bool { records[id] != nil }

    func deleteRecovery(for recoveryID: UUID) async throws {
        deletions.append(recoveryID)
        records[recoveryID] = nil
    }

    func deleteAllRecovery() async throws {
        Issue.record("Onboarding must not delete retained recovery.")
    }
}
