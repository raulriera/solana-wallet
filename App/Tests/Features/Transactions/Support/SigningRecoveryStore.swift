import Foundation
import Testing
import Vault

/// Records recovery access while keeping every test's public fixture isolated.
actor SigningRecoveryStore: RecoveryStoring {
    private let stored: Recovery
    private let error: (any Error)?
    private let gate: Suspension?
    private(set) var reads: [(recoveryID: UUID, reason: String)] = []

    /// Creates a recovery response or authentication failure for one test.
    ///
    /// - Parameters:
    ///   - recovery: Public fixture material returned by the store.
    ///   - error: An optional error raised instead of returning recovery, such as a storage error, or a
    ///     `CancellationError` when the person cancels authentication.
    ///   - gate: An optional suspension for testing cancellation during authentication.
    init(recovery: Recovery, error: (any Error)? = nil, gate: Suspension? = nil) {
        stored = recovery
        self.error = error
        self.gate = gate
    }

    /// Records the selected wallet and returns its scripted recovery.
    ///
    /// Cancellation deliberately doesn't throw here, so tests verify that the
    /// signing service checks cancellation even if a dependency returns late.
    ///
    /// - Parameters:
    ///   - recoveryID: The recovery whose access is requested.
    ///   - reason: The authentication explanation supplied by the caller.
    /// - Returns: The public recovery fixture.
    /// - Throws: The scripted error.
    func recovery(for recoveryID: UUID, reason: String) async throws -> Recovery {
        reads.append((recoveryID, reason))
        if let error { throw error }
        if let gate { await gate.suspend() }
        return stored
    }

    /// Reports an unexpected write during signing.
    ///
    /// - Parameters:
    ///   - recovery: The material the caller attempted to save.
    ///   - recoveryID: The destination identifier.
    func save(_ recovery: Recovery, for recoveryID: UUID) async throws {
        Issue.record("Signing must not save recovery material.")
    }

    /// Reports an unexpected deletion during signing.
    ///
    /// - Parameter recoveryID: The identifier the caller attempted to delete.
    func deleteRecovery(for recoveryID: UUID) async throws {
        Issue.record("Signing must not delete recovery material.")
    }

    /// Reports an unexpected deletion during signing.
    func deleteAllRecovery() async throws {
        Issue.record("Signing must not delete recovery material.")
    }
}
