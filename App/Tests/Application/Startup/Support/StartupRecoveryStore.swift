import Foundation
import Testing
import Vault

/// Counts namespace deletions while rejecting any other recovery access during startup.
actor StartupRecoveryStore: RecoveryStoring {
    private let failure: (any Error)?
    private(set) var deletions = 0

    /// Configures whether namespace deletion succeeds.
    /// - Parameter failure: The error thrown by every deletion, if any.
    init(failure: (any Error)? = nil) {
        self.failure = failure
    }

    /// Records one deletion of every recovery item.
    /// - Throws: The scripted failure.
    func deleteAllRecovery() async throws {
        deletions += 1
        if let failure { throw failure }
    }

    /// Reports an unexpected write during startup.
    /// - Parameters:
    ///   - recovery: The material the caller attempted to save.
    ///   - walletID: The destination identifier.
    func save(_ recovery: Recovery, for walletID: UUID) async throws {
        Issue.record("Startup must not save recovery material")
    }

    /// Reports an unexpected read during startup.
    /// - Parameters:
    ///   - walletID: The identifier the caller attempted to read.
    ///   - reason: The caller's authentication explanation.
    /// - Returns: Never; the test fails first.
    func recovery(for walletID: UUID, reason: String) async throws -> Recovery {
        Issue.record("Startup must not read recovery material")
        throw KeychainStore.Failure.recoveryUnavailable
    }

    /// Reports an unexpected single deletion during startup.
    /// - Parameter walletID: The identifier the caller attempted to delete.
    func deleteRecovery(for walletID: UUID) async throws {
        Issue.record("Startup must not delete one wallet's recovery")
    }
}
