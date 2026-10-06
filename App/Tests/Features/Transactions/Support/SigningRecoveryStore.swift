import Foundation
import Testing
import Vault

/// Records recovery access while keeping every test's public fixture isolated.
actor SigningRecoveryStore: RecoveryStoring {
    private let stored: Recovery
    private let failure: KeychainStore.Failure?
    private let gate: Suspension?
    private(set) var reads: [(walletID: UUID, reason: String)] = []

    /// Creates a recovery response or authentication failure for one test.
    ///
    /// - Parameters:
    ///   - recovery: Public fixture material returned by the store.
    ///   - failure: An optional storage error raised instead of returning recovery.
    ///   - gate: An optional suspension for testing cancellation during authentication.
    init(recovery: Recovery, failure: KeychainStore.Failure? = nil, gate: Suspension? = nil) {
        stored = recovery
        self.failure = failure
        self.gate = gate
    }

    /// Records the selected wallet and returns its scripted recovery.
    ///
    /// Cancellation deliberately doesn't throw here, so tests verify that the
    /// signing service checks cancellation even if a dependency returns late.
    ///
    /// - Parameters:
    ///   - walletID: The wallet whose access is requested.
    ///   - reason: The authentication explanation supplied by the caller.
    /// - Returns: The public recovery fixture.
    /// - Throws: The scripted storage failure.
    func recovery(for walletID: UUID, reason: String) async throws -> Recovery {
        reads.append((walletID, reason))
        if let failure { throw failure }
        if let gate { await gate.suspend() }
        return stored
    }

    /// Reports an unexpected write during signing.
    ///
    /// - Parameters:
    ///   - recovery: The material the caller attempted to save.
    ///   - walletID: The destination identifier.
    func save(_ recovery: Recovery, for walletID: UUID) async throws {
        Issue.record("Signing must not save recovery material.")
    }

    /// Reports an unexpected deletion during signing.
    ///
    /// - Parameter walletID: The identifier the caller attempted to delete.
    func deleteRecovery(for walletID: UUID) async throws {
        Issue.record("Signing must not delete recovery material.")
    }

    /// Reports an unexpected deletion during signing.
    func deleteAllRecovery() async throws {
        Issue.record("Signing must not delete recovery material.")
    }
}
