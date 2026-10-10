import Foundation
import Testing
import Vault

/// Isolated public-fixture recovery storage with controllable save outcomes.
actor OnboardingRecoveryStore: RecoveryStoring {
    private var records: [UUID: Recovery] = [:]
    private let firstError: (any Error)?
    private let commitBeforeError: Bool
    private let replacement: Recovery?
    private let gate: Suspension?
    private(set) var saves: [UUID] = []
    private(set) var reads: [UUID] = []

    /// Configures the first save's failure or suspension without touching the Keychain.
    /// - Parameters:
    ///   - firstError: The error thrown by the first save, if any.
    ///   - commitBeforeError: Whether that save commits before reporting failure.
    ///   - replacement: Deliberately mismatched public recovery to retain instead.
    ///   - gate: An optional cancellable suspension after the first save commits.
    init(firstError: (any Error)? = nil, commitBeforeError: Bool = false,
         replacement: Recovery? = nil, gate: Suspension? = nil) {
        self.firstError = firstError
        self.commitBeforeError = commitBeforeError
        self.replacement = replacement
        self.gate = gate
    }

    /// Saves once without replacing an existing identity and can report an ambiguous result.
    /// - Parameters:
    ///   - recovery: Public test recovery to retain.
    ///   - walletID: The draft's stable recovery identity.
    /// - Throws: The scripted first failure or a duplicate error.
    func save(_ recovery: Recovery, for walletID: UUID) async throws {
        saves.append(walletID)
        guard records[walletID] == nil else { throw KeychainStoreError.duplicateWallet }
        let error = saves.count == 1 ? firstError : nil
        if error == nil || commitBeforeError { records[walletID] = replacement ?? recovery }
        if saves.count == 1, let gate { await gate.suspend() }
        if let error { throw error }
    }

    /// Returns public fixture recovery while recording each verification read.
    /// - Parameters:
    ///   - walletID: The saved identity to read.
    ///   - reason: The caller's authentication explanation.
    /// - Returns: The retained fixture.
    /// - Throws: A missing-recovery error when no record exists.
    func recovery(for walletID: UUID, reason: String) async throws -> Recovery {
        reads.append(walletID)
        guard let recovery = records[walletID] else { throw KeychainStoreError.recoveryUnavailable }
        return recovery
    }

    /// Checks ordering without exposing fixture recovery to the account store.
    /// - Parameter id: The recovery identity required by the account.
    /// - Returns: Whether recovery was already committed.
    func contains(_ id: UUID) -> Bool { records[id] != nil }

    /// Reports any unexpected recovery deletion by onboarding.
    /// - Parameter walletID: The identity requested for deletion.
    func deleteRecovery(for walletID: UUID) async throws {
        Issue.record("Onboarding must not delete retained recovery.")
    }

    /// Reports any deletion, because onboarding never removes retained recovery.
    func deleteAllRecovery() async throws {
        Issue.record("Onboarding must not delete retained recovery.")
    }
}
