import Foundation
import Testing
import Vault
import Wallet
@testable import widgets

extension OnboardingCoordinatorTests {
    /// Committing in one window leaves another window's recovery draft and navigation intact.
    @Test
    func `Completing onboarding routes only its owning window`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let firstRouter = WindowRouter(initialDestination: .onboarding)
        let secondRouter = WindowRouter(initialDestination: .onboarding)
        let first = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts, router: firstRouter)
        let second = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts, router: secondRouter)
        try await first.importRecovery(Self.phrase, passphrase: "TREZOR")
        try await second.importRecovery(Self.phrase, passphrase: "other-window")

        let account = try await first.complete()

        #expect(firstRouter.destination == .wallet(accountID: account.id))
        #expect(first.recovery == nil)
        #expect(secondRouter.destination == .onboarding)
        #expect(second.recovery?.passphrase == "other-window")
        #expect(second.account == nil)
        #expect(await accounts.records.map(\.id) == [account.id])
    }

    /// Recovery save failures stop metadata writes while preserving the exact retry identity.
    /// - Parameter committed: Whether recovery was written before its save reported failure.
    @Test(arguments: [false, true])
    func `Failed recovery saves retain the draft and safely retry the same identity`(committed: Bool) async throws {
        let recovery = OnboardingRecoveryStore(firstFailure: NSError(domain: "private-recovery-marker", code: 1),
                                               commitBeforeFailure: committed)
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        await #expect(throws: OnboardingCoordinatorError.recoveryStorageFailed) { try await coordinator.complete() }
        #expect(coordinator.recovery != nil)
        #expect(coordinator.account == nil)
        #expect(router.destination == .onboarding)
        #expect(await accounts.additions.isEmpty)
        let account = try await coordinator.complete()
        #expect(router.destination == .wallet(accountID: account.id))
        #expect(await recovery.saves == [account.recoveryID, account.recoveryID])
        #expect(await recovery.reads.count == (committed ? 1 : 0))
        #expect(await accounts.records.count == 1)
    }

    /// Retry must verify an existing recovery instead of trusting a duplicate error alone.
    @Test
    func `A duplicate recovery containing different material cannot complete onboarding`() async throws {
        let replacement = Recovery(phrase: try RecoveryPhrase(Self.phrase), passphrase: "different")
        let recovery = OnboardingRecoveryStore(firstFailure: CancellationError(), commitBeforeFailure: true,
                                               replacement: replacement)
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        await #expect(throws: CancellationError.self) { try await coordinator.complete() }
        await #expect(throws: OnboardingCoordinatorError.recoveryMismatch) { try await coordinator.complete() }
        #expect(coordinator.account == nil)
        #expect(router.destination == .onboarding)
        #expect(coordinator.recovery != nil)
        #expect(await accounts.additions.isEmpty)
    }

    /// Metadata failures retain one recovery and one account identity across explicit retries.
    /// - Parameter committed: Whether metadata was written before failure was reported.
    @Test(arguments: [false, true])
    func `Failed account saves retry without generating or saving another recovery`(committed: Bool) async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery, firstFailure: NSError(domain: "private-marker", code: 1),
                                              commitBeforeFailure: committed)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        await #expect(throws: OnboardingCoordinatorError.accountStorageFailed) { try await coordinator.complete() }
        #expect(coordinator.recovery != nil)
        #expect(coordinator.account == nil)
        #expect(router.destination == .onboarding)
        let account = try await coordinator.complete()
        #expect(router.destination == .wallet(accountID: account.id))
        #expect(await recovery.saves == [account.recoveryID])
        #expect(await accounts.additions.map(\.id) == [account.id, account.id])
        #expect(await accounts.records.count == 1)
        #expect(coordinator.recovery == nil)
    }

    /// Duplicate metadata with a different recovery identity cannot impersonate completion.
    @Test
    func `A conflicting account record cannot complete a pending draft`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery, firstFailure: AccountStore.Failure.duplicateAccount,
                                              commitBeforeFailure: true, conflict: true)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        await #expect(throws: OnboardingCoordinatorError.accountStorageFailed) { try await coordinator.complete() }
        #expect(coordinator.account == nil)
        #expect(router.destination == .onboarding)
        #expect(coordinator.recovery != nil)
    }

    /// Reentrant completion cannot save twice, and cancelled recovery work cannot publish an account.
    @Test
    func `Cancelling recovery persistence preserves the draft and concurrent completion is rejected`() async throws {
        let gate = Suspension()
        let recovery = OnboardingRecoveryStore(gate: gate)
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        let operation = Task { try await coordinator.complete() }
        defer { operation.cancel() }
        await gate.waitUntilStarted()
        await #expect(throws: OnboardingCoordinatorError.operationInProgress) { try await coordinator.complete() }
        #expect(throws: OnboardingCoordinatorError.operationInProgress) { try coordinator.discard() }
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(coordinator.account == nil)
        #expect(router.destination == .onboarding)
        #expect(coordinator.recovery != nil)
        #expect(await accounts.additions.isEmpty)
        let account = try await coordinator.complete()
        #expect(router.destination == .wallet(accountID: account.id))
        #expect(await recovery.saves == [account.recoveryID])
    }

    /// A successful metadata commit remains successful when cancellation arrives afterwards.
    @Test
    func `Cancellation after the metadata commit still returns the saved account and routes its window`() async throws {
        let gate = Suspension()
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery, gate: gate)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        let operation = Task { try await coordinator.complete() }
        defer { operation.cancel() }
        await gate.waitUntilStarted()
        #expect(router.destination == .onboarding)
        operation.cancel()
        let account = try await operation.value
        #expect(router.destination == .wallet(accountID: account.id))
        #expect(coordinator.account?.id == account.id)
        #expect(coordinator.recovery == nil)
        #expect(await accounts.records.map(\.id) == [account.id])
    }
}
