import Foundation
import Testing
import Vault
import Wallet
@testable import widgets

extension OnboardingCoordinatorTests {
    /// Recovery save failures stop metadata writes while preserving the exact retry identity.
    /// - Parameter committed: Whether recovery was written before its save reported failure.
    @Test("failed recovery saves retain the draft and safely retry the same identity", arguments: [false, true])
    func recoverySaveCanRetry(committed: Bool) async throws {
        let recovery = OnboardingRecoveryStore(firstFailure: NSError(domain: "private-recovery-marker", code: 1),
                                               commitBeforeFailure: committed)
        let accounts = OnboardingAccountStore(recovery: recovery)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        await #expect(throws: OnboardingCoordinatorError.recoveryStorageFailed) { try await coordinator.complete() }
        #expect(coordinator.recovery != nil)
        #expect(coordinator.account == nil)
        #expect(await accounts.additions.isEmpty)
        let account = try await coordinator.complete()
        #expect(await recovery.saves == [account.recoveryID, account.recoveryID])
        #expect(await recovery.reads.count == (committed ? 1 : 0))
        #expect(await accounts.records.count == 1)
    }

    /// Retry must verify an existing recovery instead of trusting a duplicate error alone.
    @Test("a duplicate recovery containing different material cannot complete onboarding")
    func duplicateRecoveryMustMatch() async throws {
        let replacement = Recovery(phrase: try RecoveryPhrase(Self.phrase), passphrase: "different")
        let recovery = OnboardingRecoveryStore(firstFailure: CancellationError(), commitBeforeFailure: true,
                                               replacement: replacement)
        let accounts = OnboardingAccountStore(recovery: recovery)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        await #expect(throws: CancellationError.self) { try await coordinator.complete() }
        await #expect(throws: OnboardingCoordinatorError.recoveryMismatch) { try await coordinator.complete() }
        #expect(coordinator.account == nil)
        #expect(coordinator.recovery != nil)
        #expect(await accounts.additions.isEmpty)
    }

    /// Metadata failures retain one recovery and one account identity across explicit retries.
    /// - Parameter committed: Whether metadata was written before failure was reported.
    @Test("failed account saves retry without generating or saving another recovery", arguments: [false, true])
    func accountSaveCanRetry(committed: Bool) async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery, firstFailure: NSError(domain: "private-marker", code: 1),
                                              commitBeforeFailure: committed)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        await #expect(throws: OnboardingCoordinatorError.accountStorageFailed) { try await coordinator.complete() }
        #expect(coordinator.recovery != nil)
        #expect(coordinator.account == nil)
        let account = try await coordinator.complete()
        #expect(await recovery.saves == [account.recoveryID])
        #expect(await accounts.additions.map(\.id) == [account.id, account.id])
        #expect(await accounts.records.count == 1)
        #expect(coordinator.recovery == nil)
    }

    /// Duplicate metadata with a different recovery identity cannot impersonate completion.
    @Test("a conflicting account record cannot complete a pending draft")
    func duplicateAccountMustMatch() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery, firstFailure: AccountStore.Failure.duplicateAccount,
                                              commitBeforeFailure: true, conflict: true)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        await #expect(throws: OnboardingCoordinatorError.accountStorageFailed) { try await coordinator.complete() }
        #expect(coordinator.account == nil)
        #expect(coordinator.recovery != nil)
    }

    /// Reentrant completion cannot save twice, and cancelled recovery work cannot publish an account.
    @Test("cancelling recovery persistence preserves the draft and concurrent completion is rejected")
    func cancelledRecoveryCanRetry() async throws {
        let gate = Suspension()
        let recovery = OnboardingRecoveryStore(gate: gate)
        let accounts = OnboardingAccountStore(recovery: recovery)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        let operation = Task { try await coordinator.complete() }
        defer { operation.cancel() }
        await gate.waitUntilStarted()
        await #expect(throws: OnboardingCoordinatorError.operationInProgress) { try await coordinator.complete() }
        #expect(throws: OnboardingCoordinatorError.operationInProgress) { try coordinator.discard() }
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(coordinator.account == nil)
        #expect(coordinator.recovery != nil)
        #expect(await accounts.additions.isEmpty)
        let account = try await coordinator.complete()
        #expect(await recovery.saves == [account.recoveryID])
    }

    /// A successful metadata commit remains successful when cancellation arrives afterwards.
    @Test("cancellation after the metadata commit still returns the saved account")
    func lateCancellationKeepsCommittedAccount() async throws {
        let gate = Suspension()
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery, gate: gate)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        let operation = Task { try await coordinator.complete() }
        defer { operation.cancel() }
        await gate.waitUntilStarted()
        operation.cancel()
        let account = try await operation.value
        #expect(coordinator.account?.id == account.id)
        #expect(coordinator.recovery == nil)
        #expect(await accounts.records.map(\.id) == [account.id])
    }
}
