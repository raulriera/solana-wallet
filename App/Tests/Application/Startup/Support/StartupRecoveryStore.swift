import Foundation
import Testing
import Vault

actor StartupRecoveryStore: RecoveryStoring {
    private let error: (any Error)?
    private(set) var deletions = 0

    init(error: (any Error)? = nil) {
        self.error = error
    }

    func deleteAllRecovery() async throws {
        deletions += 1
        if let error { throw error }
    }

    func save(_ recovery: Recovery, for recoveryID: UUID) async throws {
        Issue.record("Startup must not save recovery material")
    }

    func recovery(for recoveryID: UUID, reason: String) async throws -> Recovery {
        Issue.record("Startup must not read recovery material")
        throw KeychainStoreError.recoveryUnavailable
    }

    func deleteRecovery(for recoveryID: UUID) async throws {
        Issue.record("Startup must not delete one wallet's recovery")
    }
}
