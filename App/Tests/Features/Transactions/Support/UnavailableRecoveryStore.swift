import Foundation
import Testing
import Vault

/// A recovery store that fails the test on any access, for signers that must not read recovery.
struct UnavailableRecoveryStore: RecoveryStoring {
    /// Creates a store with no recovery material.
    init() {}

    /// Reports an unexpected read and fails it.
    ///
    /// - Parameters:
    ///   - recoveryID: The recovery whose access was requested.
    ///   - reason: The authentication explanation supplied by the caller.
    /// - Returns: Never returns.
    /// - Throws: ``KeychainStoreError/recoveryUnavailable`` after recording the issue.
    func recovery(for recoveryID: UUID, reason: String) async throws -> Recovery {
        Issue.record("A one-time account must not read recovery material.")
        throw KeychainStoreError.recoveryUnavailable
    }

    /// Reports an unexpected write.
    ///
    /// - Parameters:
    ///   - recovery: The material the caller attempted to save.
    ///   - recoveryID: The destination identifier.
    func save(_ recovery: Recovery, for recoveryID: UUID) async throws {
        Issue.record("Signing must not save recovery material.")
    }

    /// Reports an unexpected deletion.
    ///
    /// - Parameter recoveryID: The identifier the caller attempted to delete.
    func deleteRecovery(for recoveryID: UUID) async throws {
        Issue.record("Signing must not delete recovery material.")
    }

    /// Reports an unexpected deletion.
    func deleteAllRecovery() async throws {
        Issue.record("Signing must not delete recovery material.")
    }
}
