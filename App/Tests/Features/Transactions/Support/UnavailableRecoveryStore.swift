import Foundation
import Testing
import Vault

struct UnavailableRecoveryStore: RecoveryStoring {
    init() {}

    func recovery(for recoveryID: UUID, reason: String) async throws -> Recovery {
        Issue.record("A one-time account must not read recovery material.")
        throw KeychainStoreError.recoveryUnavailable
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
