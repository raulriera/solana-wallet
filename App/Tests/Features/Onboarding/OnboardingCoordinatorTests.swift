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
    @Test
    func `Creating a wallet prepares twelve words without persisting recovery or accounts`() async throws {
        let http = HTTPResponses.discovery()
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator: any OnboardingCoordinating = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        try await coordinator.create()
        #expect(coordinator.recovery?.phrase.words.count == 12)
        #expect(coordinator.recovery?.passphrase.isEmpty == true)
        #expect(coordinator.account == nil)
        #expect(router.destination == .onboarding)
        #expect(!coordinator.isWorking)
        #expect(await recovery.saves.isEmpty)
        #expect(await accounts.additions.isEmpty)
        #expect(await http.requests.isEmpty)
        try coordinator.discard()
        #expect(coordinator.recovery == nil)
    }

    /// Imports a published fixture and commits the independently known index-zero address.
    @Test
    func `Explicit completion saves imported recovery before its first account and clears the draft`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        #expect(await recovery.saves.isEmpty)
        let account = try await coordinator.complete()
        #expect(router.destination == .wallet(accountID: account.id))
        #expect(account.address.value == "7zSmbu6gKkb6HB7UDPtHYjwCWuBHU1D4TpNZFm4sndQe")
        #expect(account.path == .solana)
        #expect(coordinator.account?.id == account.id)
        #expect(coordinator.recovery == nil)
        #expect(try await coordinator.complete().id == account.id)
        #expect(await recovery.saves == [account.recoveryID])
        #expect(await accounts.additions.map(\.id) == [account.id])
    }

    /// Separate windows keep their drafts and original passphrases independent.
    @Test
    func `Window drafts preserve passphrase whitespace and cannot clear another window`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let firstRouter = WindowRouter(initialDestination: .onboarding)
        let secondRouter = WindowRouter(initialDestination: .onboarding)
        let first = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: firstRouter)
        let second = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: secondRouter)
        try await first.importRecovery(Self.phrase, passphrase: " TREZOR ")
        try await second.importRecovery(Self.phrase, passphrase: "TREZOR")
        #expect(first.recovery?.passphrase == " TREZOR ")
        try first.discard()
        #expect(first.recovery == nil)
        #expect(second.recovery?.passphrase == "TREZOR")
        #expect(await recovery.saves.isEmpty)
    }

    /// Invalid recovery never reaches either persistence boundary.
    @Test
    func `Invalid recovery reports validation without storing supplied text`() async throws {
        let http = HTTPResponses.discovery()
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        await #expect(throws: RecoveryPhrase.ValidationError.invalidWordCount) {
            try await coordinator.importRecovery("private-input-marker", passphrase: "private-passphrase-marker")
        }
        #expect(coordinator.recovery == nil)
        #expect(coordinator.account == nil)
        #expect(router.destination == .onboarding)
        #expect(await recovery.saves.isEmpty)
        #expect(await accounts.additions.isEmpty)
        #expect(await http.requests.isEmpty)
    }

    /// An unapproved draft cannot be replaced by a second preparation action.
    @Test
    func `Completion requires a draft and preparing again cannot replace one`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        await #expect(throws: OnboardingCoordinatorError.draftRequired) { try await coordinator.complete() }
        try await coordinator.importRecovery(Self.phrase, passphrase: "TREZOR")
        await #expect(throws: OnboardingCoordinatorError.draftAlreadyPrepared) { try await coordinator.create() }
        #expect(coordinator.recovery?.passphrase == "TREZOR")
        #expect(await recovery.saves.isEmpty)
    }

    /// Derivation errors from injected services cannot escape with recovery text.
    @Test
    func `Preparation errors do not expose underlying secret text`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let error = NSError(domain: "private-recovery-marker", code: 1)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: OnboardingWallet(failure: error), recovery: recovery, accounts: accounts, router: router)
        await #expect(throws: OnboardingCoordinatorError.preparationFailed) {
            try await coordinator.importRecovery(Self.phrase, passphrase: "private-passphrase-marker")
        }
        #expect(coordinator.recovery == nil)
        #expect(!String(reflecting: coordinator).contains("private-passphrase-marker"))
    }

    /// Cancelled derivation cannot publish a late recovery draft or make storage calls.
    @Test
    func `Cancelling preparation rejects a late derived address without publishing recovery`() async throws {
        let gate = Suspension()
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: OnboardingWallet(gate: gate), recovery: recovery, accounts: accounts, router: router)
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
