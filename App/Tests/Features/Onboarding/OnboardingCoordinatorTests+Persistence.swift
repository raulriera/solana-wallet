import Foundation
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

extension OnboardingCoordinatorTests {
    /// Known Vault failures preserve context while unknown dependency payloads remain redacted.
    @Test
    func `Recovery storage preserves its typed protection failure without wrapping secret text`() async throws {
        let recovery = OnboardingRecoveryStore(firstError: KeychainStoreError.protectionUnavailable)
        let accounts = AccountStore.inMemory()
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")

        await #expect(throws: KeychainStoreError.protectionUnavailable) { try await coordinator.complete() }

        #expect(coordinator.recovery != nil)
        #expect(accounts.accounts.isEmpty)
    }

    /// An account already saved at the imported address keeps its typed error and can't complete the draft.
    @Test
    func `A duplicate account keeps its typed error and the draft`() async throws {
        let recovery = OnboardingRecoveryStore()
        let saved = widgets.Account(id: UUID(), recoveryID: UUID(),
                                    address: try Address("7zSmbu6gKkb6HB7UDPtHYjwCWuBHU1D4TpNZFm4sndQe"),
                                    path: .solana)
        let storage = StoredValue([saved])
        let accounts = AccountStore.inMemory(storage)
        await accounts.load()
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")

        await #expect(throws: AccountStoreError.duplicateAccount) { try await coordinator.complete() }

        #expect(coordinator.account == nil)
        #expect(coordinator.recovery != nil)
        #expect(router.destination == .onboarding)
        #expect(await storage.value == [saved])
    }

    /// Finishing in one window leaves another window's recovery draft and navigation intact.
    @Test
    func `Finishing onboarding routes only its owning window`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let firstRouter = WindowRouter(initialDestination: .onboarding)
        let secondRouter = WindowRouter(initialDestination: .onboarding)
        let first = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: firstRouter)
        let second = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: secondRouter)
        try await first.importRecovery(Self.phrase, passphrase: "TREZOR")
        try await second.importRecovery(Self.phrase, passphrase: "other-window")

        let account = try await first.complete()
        try first.finish()

        #expect(firstRouter.destination == .wallet(account))
        #expect(first.recovery == nil)
        #expect(secondRouter.destination == .onboarding)
        #expect(second.recovery?.passphrase == "other-window")
        #expect(second.account == nil)
        #expect(accounts.accounts.map(\.id) == [account.id])
    }

    /// Recovery save failures stop metadata writes while preserving the exact retry identity.
    /// - Parameter committed: Whether recovery was written before its save reported failure.
    @Test(arguments: [false, true])
    func `Failed recovery saves retain the draft and safely retry the same identity`(committed: Bool) async throws {
        let recovery = OnboardingRecoveryStore(firstError: NSError(domain: "private-recovery-marker", code: 1),
                                               commitBeforeError: committed)
        let accounts = AccountStore.inMemory()
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        await #expect(throws: OnboardingCoordinatorError.recoveryStorageFailed) { try await coordinator.complete() }
        #expect(coordinator.recovery != nil)
        #expect(coordinator.account == nil)
        #expect(router.destination == .onboarding)
        #expect(accounts.accounts.isEmpty)
        let account = try await coordinator.complete()
        #expect(coordinator.account?.id == account.id)
        #expect(await recovery.saves == [account.recoveryID, account.recoveryID])
        #expect(await recovery.reads.count == (committed ? 1 : 0))
        #expect(accounts.accounts.count == 1)
    }

    /// Retry must verify an existing recovery instead of trusting a duplicate error alone.
    @Test
    func `A duplicate recovery containing different material cannot complete onboarding`() async throws {
        let replacement = Recovery(phrase: try RecoveryPhrase(Self.phrase), passphrase: "different")
        let recovery = OnboardingRecoveryStore(firstError: CancellationError(), commitBeforeError: true,
                                               replacement: replacement)
        let accounts = AccountStore.inMemory()
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        await #expect(throws: CancellationError.self) { try await coordinator.complete() }
        await #expect(throws: OnboardingCoordinatorError.recoveryMismatch) { try await coordinator.complete() }
        #expect(coordinator.account == nil)
        #expect(router.destination == .onboarding)
        #expect(coordinator.recovery != nil)
        #expect(accounts.accounts.isEmpty)
    }

    /// A failed account save keeps one recovery and one account identity for an explicit retry.
    @Test
    func `Failed account saves retry without generating or saving another recovery`() async throws {
        let recovery = OnboardingRecoveryStore()
        let storage = StoredValue<[widgets.Account]>(failsSaving: true)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: .inMemory(storage), router: router)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        await #expect(throws: OnboardingCoordinatorError.accountStorageFailed) { try await coordinator.complete() }
        #expect(coordinator.recovery != nil)
        #expect(coordinator.account == nil)
        #expect(router.destination == .onboarding)
        await storage.failSaving(false)
        let account = try await coordinator.complete()
        #expect(coordinator.account?.id == account.id)
        #expect(await recovery.saves == [account.recoveryID])
        #expect(await storage.value == [account])
        #expect(coordinator.recovery == nil)
    }

    /// Reentrant completion cannot save twice, and cancelled recovery work cannot publish an account.
    @Test
    func `Cancelling recovery persistence preserves the draft and concurrent completion is rejected`() async throws {
        let gate = Suspension()
        let recovery = OnboardingRecoveryStore(gate: gate)
        let accounts = AccountStore.inMemory()
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
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
        #expect(accounts.accounts.isEmpty)
        let account = try await coordinator.complete()
        #expect(coordinator.account?.id == account.id)
        #expect(await recovery.saves == [account.recoveryID])
    }

    /// A successful metadata commit remains successful when cancellation arrives afterwards.
    @Test
    func `Cancellation after the metadata commit still returns the saved account`() async throws {
        let gate = Suspension()
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory(StoredValue(gate: gate))
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        let operation = Task { try await coordinator.complete() }
        defer { operation.cancel() }
        await gate.waitUntilStarted()
        operation.cancel()
        // Cancellation doesn't stop a save that started, so the saved account waits only for the storage.
        gate.resume()
        let account = try await operation.value
        #expect(coordinator.account?.id == account.id)
        #expect(coordinator.recovery == nil)
        #expect(accounts.accounts.map(\.id) == [account.id])
    }
}
