import Foundation
import Testing
import Vault

actor SigningRecoveryStore: RecoveryStoring {
    private let stored: Recovery
    private let error: (any Error)?
    private let gate: Suspension?
    private(set) var reads: [(recoveryID: UUID, reason: String)] = []
    private(set) var shared: [(reason: String, store: SigningRecoveryStore)] = []

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

    func withSharedAuthentication<Value: Sendable>(
        reason: String, _ operation: @Sendable (any RecoveryStoring) async throws -> Value
    ) async throws -> Value {
        let store = SigningRecoveryStore(recovery: stored, error: error, gate: gate)
        shared.append((reason, store))
        return try await operation(store)
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
