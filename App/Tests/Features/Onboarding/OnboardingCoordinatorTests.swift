import Foundation
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct OnboardingCoordinatorTests {
    @Test
    func `Creating a wallet prepares twelve words without persisting recovery or accounts`() async throws {
        let http = HTTPResponses.discovery()
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let coordinator: any OnboardingCoordinating = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await coordinator.create()
        #expect(coordinator.recovery?.phrase.words.count == 12)
        #expect(coordinator.recovery?.passphrase.isEmpty == true)
        #expect(coordinator.account == nil)
        #expect(coordinator.finishedAccount == nil)
        #expect(!coordinator.isWorking)
        #expect(await recovery.saves.isEmpty)
        #expect(accounts.accounts.isEmpty)
        #expect(await http.requests.isEmpty)
        try coordinator.discard()
        #expect(coordinator.recovery == nil)
    }

    @Test
    func `Explicit completion saves imported recovery before its first account and clears the draft`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await coordinator.importRecovery(PublicWallet.words, passphrase: "TREZOR")
        #expect(await recovery.saves.isEmpty)
        let account = try await coordinator.complete()
        #expect(coordinator.finishedAccount == nil)
        #expect(account.address.value == "7zSmbu6gKkb6HB7UDPtHYjwCWuBHU1D4TpNZFm4sndQe")
        #expect(account.path == .solana)
        #expect(coordinator.account?.id == account.id)
        #expect(coordinator.recovery == nil)
        #expect(try await coordinator.complete().id == account.id)
        #expect(await recovery.saves == [account.recoveryID])
        #expect(accounts.accounts.map(\.id) == [account.id])
    }

    @Test
    func `Finishing opens the saved account even after its draft is released`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await coordinator.importRecovery(PublicWallet.words, passphrase: "TREZOR")
        let account = try await coordinator.complete()
        try coordinator.discard()

        try coordinator.finish()

        #expect(coordinator.account?.id == account.id)
        #expect(coordinator.finishedAccount == account)
    }

    @Test
    func `Finishing before completion is rejected and keeps the window in onboarding`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await coordinator.importRecovery(PublicWallet.words, passphrase: "TREZOR")

        #expect(throws: OnboardingCoordinatorError.accountRequired) { try coordinator.finish() }

        #expect(coordinator.finishedAccount == nil)
        #expect(coordinator.recovery != nil)
    }

    @Test
    func `Window drafts preserve passphrase whitespace and cannot clear another window`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let first = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        let second = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        try await first.importRecovery(PublicWallet.words, passphrase: " TREZOR ")
        try await second.importRecovery(PublicWallet.words, passphrase: "TREZOR")
        #expect(first.recovery?.passphrase == " TREZOR ")
        try first.discard()
        #expect(first.recovery == nil)
        #expect(second.recovery?.passphrase == "TREZOR")
        #expect(await recovery.saves.isEmpty)
    }

    @Test
    func `Invalid recovery reports validation without storing supplied text`() async throws {
        let http = HTTPResponses.discovery()
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        await #expect(throws: RecoveryPhrase.ValidationError.invalidWordCount) {
            try await coordinator.importRecovery("private-input-marker", passphrase: "private-passphrase-marker")
        }
        #expect(coordinator.recovery == nil)
        #expect(coordinator.account == nil)
        #expect(coordinator.finishedAccount == nil)
        #expect(await recovery.saves.isEmpty)
        #expect(accounts.accounts.isEmpty)
        #expect(await http.requests.isEmpty)
    }

    @Test
    func `Completion requires a draft and preparing again cannot replace one`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        await #expect(throws: OnboardingCoordinatorError.draftRequired) { try await coordinator.complete() }
        try await coordinator.importRecovery(PublicWallet.words, passphrase: "TREZOR")
        await #expect(throws: OnboardingCoordinatorError.draftAlreadyPrepared) { try await coordinator.create() }
        #expect(coordinator.recovery?.passphrase == "TREZOR")
        #expect(await recovery.saves.isEmpty)
    }

    @Test
    func `Preparation errors do not expose underlying secret text`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let error = NSError(domain: "private-recovery-marker", code: 1)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: OnboardingWallet(error: error), recovery: recovery, accounts: accounts)
        await #expect(throws: OnboardingCoordinatorError.preparationFailed) {
            try await coordinator.importRecovery(PublicWallet.words, passphrase: "private-passphrase-marker")
        }
        #expect(coordinator.recovery == nil)
        #expect(!String(reflecting: coordinator).contains("private-passphrase-marker"))
    }

    @Test
    func `Cancelling preparation rejects a late derived address without publishing recovery`() async throws {
        let gate = Suspension()
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: OnboardingWallet(gate: gate), recovery: recovery, accounts: accounts)
        let operation = Task { try await coordinator.importRecovery(PublicWallet.words, passphrase: "") }
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
        #expect(accounts.accounts.isEmpty)
    }
}
