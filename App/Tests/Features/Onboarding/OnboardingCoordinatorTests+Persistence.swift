import Foundation
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

extension OnboardingCoordinatorTests {
    @Test
    func `Recovery storage preserves its typed protection failure without wrapping secret text`() async throws {
        let recovery = OnboardingRecoveryStore(firstError: KeychainStoreError.protectionUnavailable)
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")

        await #expect(throws: KeychainStoreError.protectionUnavailable) { try await coordinator.complete() }

        #expect(coordinator.recovery != nil)
        #expect(accounts.accounts.isEmpty)
    }

    @Test
    func `A duplicate account keeps its typed error and the draft`() async throws {
        let recovery = OnboardingRecoveryStore()
        let saved = widgets.Account(id: UUID(), recoveryID: UUID(),
                                    address: try Address("7zSmbu6gKkb6HB7UDPtHYjwCWuBHU1D4TpNZFm4sndQe"),
                                    path: .solana)
        let storage = StoredValue([saved])
        let accounts = AccountStore.inMemory(storage)
        await accounts.load()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")

        await #expect(throws: AccountStoreError.duplicateAccount) { try await coordinator.complete() }

        #expect(coordinator.account == nil)
        #expect(coordinator.recovery != nil)
        #expect(coordinator.finishedAccount == nil)
        #expect(await storage.value == [saved])
    }

    @Test
    func `Finishing onboarding finishes only its owning window's draft`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let first = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        let second = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await first.importRecovery(Self.phrase, passphrase: "TREZOR")
        try await second.importRecovery(Self.phrase, passphrase: "other-window")

        let account = try await first.complete()
        try first.finish()

        #expect(first.finishedAccount == account)
        #expect(first.recovery == nil)
        #expect(second.finishedAccount == nil)
        #expect(second.recovery?.passphrase == "other-window")
        #expect(second.account == nil)
        #expect(accounts.accounts.map(\.id) == [account.id])
    }

    @Test(arguments: [false, true])
    func `Failed recovery saves retain the draft and safely retry the same identity`(committed: Bool) async throws {
        let recovery = OnboardingRecoveryStore(firstError: NSError(domain: "private-recovery-marker", code: 1),
                                               commitBeforeError: committed)
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        await #expect(throws: OnboardingCoordinatorError.recoveryStorageFailed) { try await coordinator.complete() }
        #expect(coordinator.recovery != nil)
        #expect(coordinator.account == nil)
        #expect(coordinator.finishedAccount == nil)
        #expect(accounts.accounts.isEmpty)
        let account = try await coordinator.complete()
        #expect(coordinator.account?.id == account.id)
        #expect(await recovery.saves == [account.recoveryID, account.recoveryID])
        #expect(await recovery.reads.count == (committed ? 1 : 0))
        #expect(accounts.accounts.count == 1)
    }

    @Test
    func `A duplicate recovery containing different material cannot complete onboarding`() async throws {
        let replacement = Recovery(phrase: try RecoveryPhrase(Self.phrase), passphrase: "different")
        let recovery = OnboardingRecoveryStore(firstError: CancellationError(), commitBeforeError: true,
                                               replacement: replacement)
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        await #expect(throws: CancellationError.self) { try await coordinator.complete() }
        await #expect(throws: OnboardingCoordinatorError.recoveryMismatch) { try await coordinator.complete() }
        #expect(coordinator.account == nil)
        #expect(coordinator.finishedAccount == nil)
        #expect(coordinator.recovery != nil)
        #expect(accounts.accounts.isEmpty)
    }

    @Test
    func `Failed account saves retry without generating or saving another recovery`() async throws {
        let recovery = OnboardingRecoveryStore()
        let storage = StoredValue<[widgets.Account]>(failsSaving: true)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: .inMemory(storage))
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        await #expect(throws: OnboardingCoordinatorError.accountStorageFailed) { try await coordinator.complete() }
        #expect(coordinator.recovery != nil)
        #expect(coordinator.account == nil)
        #expect(coordinator.finishedAccount == nil)
        await storage.failSaving(false)
        let account = try await coordinator.complete()
        #expect(coordinator.account?.id == account.id)
        #expect(await recovery.saves == [account.recoveryID])
        #expect(await storage.value == [account])
        #expect(coordinator.recovery == nil)
    }

    @Test
    func `Cancelling recovery persistence preserves the draft and concurrent completion is rejected`() async throws {
        let gate = Suspension()
        let recovery = OnboardingRecoveryStore(gate: gate)
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        let operation = Task { try await coordinator.complete() }
        defer { operation.cancel() }
        await gate.waitUntilStarted()
        await #expect(throws: OnboardingCoordinatorError.operationInProgress) { try await coordinator.complete() }
        #expect(throws: OnboardingCoordinatorError.operationInProgress) { try coordinator.discard() }
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(coordinator.account == nil)
        #expect(coordinator.finishedAccount == nil)
        #expect(coordinator.recovery != nil)
        #expect(accounts.accounts.isEmpty)
        let account = try await coordinator.complete()
        #expect(coordinator.account?.id == account.id)
        #expect(await recovery.saves == [account.recoveryID])
    }

    @Test
    func `Cancellation after the metadata commit still returns the saved account`() async throws {
        let gate = Suspension()
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory(StoredValue(gate: gate))
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        let operation = Task { try await coordinator.complete() }
        defer { operation.cancel() }
        await gate.waitUntilStarted()
        operation.cancel()
        gate.resume()
        let account = try await operation.value
        #expect(coordinator.account?.id == account.id)
        #expect(coordinator.recovery == nil)
        #expect(accounts.accounts.map(\.id) == [account.id])
    }
}
