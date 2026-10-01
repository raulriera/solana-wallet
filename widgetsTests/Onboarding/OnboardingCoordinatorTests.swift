import Foundation
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

/// Verifies explicit onboarding approval with isolated stores and published BIP-39 fixtures.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct OnboardingCoordinatorTests {
    static let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

    /// New recovery stays only in memory until the caller explicitly completes onboarding.
    @Test("creating a wallet prepares twelve words without persisting recovery or accounts")
    func creationWaitsForApproval() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let coordinator: any OnboardingCoordinating = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await coordinator.create()
        #expect(coordinator.recovery?.phrase.words.count == 12)
        #expect(coordinator.recovery?.passphrase.isEmpty == true)
        #expect(coordinator.account == nil)
        #expect(!coordinator.isWorking)
        #expect(await recovery.saves.isEmpty)
        #expect(await accounts.additions.isEmpty)
        try coordinator.discard()
        #expect(coordinator.recovery == nil)
    }

    /// Imports a published fixture and commits the independently known index-zero address.
    @Test("explicit completion saves imported recovery before its first account and clears the draft")
    func importedAccountCompletesOnce() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        #expect(await recovery.saves.isEmpty)
        let account = try await coordinator.complete()
        #expect(account.address.value == "7zSmbu6gKkb6HB7UDPtHYjwCWuBHU1D4TpNZFm4sndQe")
        #expect(account.index == 0)
        #expect(try account.path == .solana)
        #expect(coordinator.account?.id == account.id)
        #expect(coordinator.recovery == nil)
        #expect(try await coordinator.complete().id == account.id)
        #expect(await recovery.saves == [account.recoveryID])
        #expect(await accounts.additions.map(\.id) == [account.id])
    }

    /// Separate windows keep their drafts and original passphrases independent.
    @Test("window drafts preserve passphrase whitespace and cannot clear another window")
    func windowDraftsAreIndependent() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let first = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts)
        let second = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await first.importRecovery(Self.phrase, passphrase: " TREZOR ")
        try await second.importRecovery(Self.phrase, passphrase: "TREZOR")
        #expect(first.recovery?.passphrase == " TREZOR ")
        try first.discard()
        #expect(first.recovery == nil)
        #expect(second.recovery?.passphrase == "TREZOR")
        #expect(await recovery.saves.isEmpty)
    }

    /// Invalid recovery never reaches either persistence boundary.
    @Test("invalid recovery reports validation without storing supplied text")
    func invalidImportIsRejected() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts)
        await #expect(throws: RecoveryPhrase.ValidationError.invalidWordCount) {
            try await coordinator.importRecovery("private-input-marker", passphrase: "private-passphrase-marker")
        }
        #expect(coordinator.recovery == nil)
        #expect(coordinator.account == nil)
        #expect(await recovery.saves.isEmpty)
        #expect(await accounts.additions.isEmpty)
    }

    /// An unapproved draft cannot be replaced by a second preparation action.
    @Test("completion requires a draft and preparing again cannot replace one")
    func draftTransitionsAreExplicit() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts)
        await #expect(throws: OnboardingCoordinatorError.draftRequired) { try await coordinator.complete() }
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        await #expect(throws: OnboardingCoordinatorError.draftAlreadyPrepared) { try await coordinator.create() }
        #expect(coordinator.recovery?.passphrase == "TREZOR")
        #expect(await recovery.saves.isEmpty)
    }

    /// Derivation errors from injected services cannot escape with recovery text.
    @Test("preparation errors do not expose underlying secret text")
    func preparationErrorsAreRedacted() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let error = NSError(domain: "private-recovery-marker", code: 1)
        let coordinator = OnboardingCoordinator(wallet: OnboardingWallet(failure: error), recovery: recovery, accounts: accounts)
        await #expect(throws: OnboardingCoordinatorError.preparationFailed) {
            try await coordinator.importRecovery(Self.phrase, passphrase: "private-passphrase-marker")
        }
        #expect(coordinator.recovery == nil)
        #expect(!String(reflecting: coordinator).contains("private-passphrase-marker"))
    }

    /// Cancelled derivation cannot publish a late recovery draft or make storage calls.
    @Test("cancelling preparation rejects a late derived address without publishing recovery")
    func cancelledPreparationLeavesNoDraft() async throws {
        let gate = Suspension()
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let coordinator = OnboardingCoordinator(wallet: OnboardingWallet(gate: gate), recovery: recovery, accounts: accounts)
        let operation = Task { try await coordinator.importRecovery(Self.phrase, passphrase: "") }
        defer { operation.cancel() }
        await gate.waitUntilStarted()
        try Task.checkCancellation()
        #expect(coordinator.isWorking)
        #expect(coordinator.recovery == nil)
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(coordinator.recovery == nil)
        #expect(!coordinator.isWorking)
        #expect(await recovery.saves.isEmpty)
        #expect(await accounts.additions.isEmpty)
    }
}
