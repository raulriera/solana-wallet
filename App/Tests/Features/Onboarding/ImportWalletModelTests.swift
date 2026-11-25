import Foundation
import RPC
import Testing
import Vault
import Wallet
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ImportWalletModelTests {
    private static let phrase = OnboardingCoordinatorTests.phrase

    @Test
    func `Repeated submission and task evaluation complete one accepted import`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        let submission = ImportWalletModel(coordinator: coordinator)
        submission.present()
        submission.submit(Self.phrase, passphrase: " TrEzOr ")
        let attempt = try #require(submission.attempt)
        submission.submit(Self.phrase, passphrase: "different")
        #expect(submission.attempt == attempt)
        #expect(submission.isPending)
        #expect(await recovery.saves.isEmpty)

        await submission.run(attempt)
        await submission.run(attempt)
        submission.submit(Self.phrase, passphrase: "different")
        #expect(submission.attempt == nil)

        let account = try #require(coordinator.account)
        let saved = try await recovery.recovery(for: account.recoveryID, reason: "Read public test fixture")
        #expect(saved.passphrase == " TrEzOr ")
        #expect(coordinator.finishedAccount == nil)
        #expect(await recovery.saves.count == 1)
        #expect(accounts.accounts.count == 1)
        #expect(!submission.isPending)
        #expect(submission.error == nil)
    }

    @Test
    func `Persistence retry keeps the draft identity and skips committed recovery`() async throws {
        let http = HTTPResponses.discovery(fundedOffsets: [1])
        let recovery = OnboardingRecoveryStore()
        let storage = StoredValue<[widgets.Account]>(failsSaving: true)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(), recovery: recovery, accounts: .inMemory(storage))
        let submission = ImportWalletModel(coordinator: coordinator)
        submission.present()
        submission.submit(Self.phrase, passphrase: "TREZOR")
        await submission.run(submission.attempt)
        #expect(submission.error == .saveFailed)
        #expect(coordinator.finishedAccount == nil)
        let recoveryID = try #require(await recovery.saves.first)

        await storage.failSaving(false)
        submission.submit("  " + Self.phrase.replacingOccurrences(of: " ", with: "\n") + "  ", passphrase: "TREZOR")
        #expect(submission.error == nil)
        await submission.run(submission.attempt)

        let account = try #require(coordinator.account)
        #expect(account.recoveryID == recoveryID)
        #expect(await recovery.saves == [recoveryID])
        #expect(await storage.value == [account])
        #expect(account.path.description == "m/44'/501'/0'")
        #expect(await http.requests.count == 1)
    }

    @Test(arguments: ["trezor", " TREZOR "])
    func `Changed input starts a new import while retaining previously saved recovery`(passphrase: String) async throws {
        let recovery = OnboardingRecoveryStore()
        let storage = StoredValue<[widgets.Account]>(failsSaving: true)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: .inMemory(storage))
        let submission = ImportWalletModel(coordinator: coordinator)
        submission.present()
        submission.submit(Self.phrase, passphrase: "TREZOR")
        await submission.run(submission.attempt)
        let original = try #require(await recovery.saves.first)

        await storage.failSaving(false)
        submission.submit(Self.phrase, passphrase: passphrase)
        await submission.run(submission.attempt)

        let imported = try #require(coordinator.account)
        #expect(imported.recoveryID != original)
        #expect(await recovery.contains(original))
        #expect(await recovery.contains(imported.recoveryID))
        let saved = try await recovery.recovery(for: imported.recoveryID, reason: "Read public test fixture")
        #expect(saved.passphrase == passphrase)
    }

    @Test
    func `Preparation failure permits another explicit attempt without saving anything`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let wallet = OnboardingWallet(error: NSError(domain: "private-marker", code: 1))
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: wallet, recovery: recovery, accounts: accounts)
        let submission = ImportWalletModel(coordinator: coordinator)
        submission.present()
        submission.submit(Self.phrase, passphrase: "TREZOR")
        let attempt = try #require(submission.attempt)
        await submission.run(attempt)
        #expect(submission.error == .preparationFailed)
        #expect(!submission.isPending)
        #expect(coordinator.recovery == nil)

        submission.submit(Self.phrase, passphrase: "TREZOR")
        #expect(submission.attempt != nil)
        #expect(submission.attempt != attempt)
        #expect(submission.error == nil)
        await submission.run(submission.attempt)
        #expect(await recovery.saves.isEmpty)
        #expect(accounts.accounts.isEmpty)
    }

    @Test
    func `A rate-limited account lookup explains the limit`() async {
        let http = HTTPResponses.discovery(error: .http(statusCode: 429, retryAfter: "3"))
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        let submission = ImportWalletModel(coordinator: coordinator)
        submission.present()
        submission.submit(Self.phrase, passphrase: "TREZOR")

        await submission.run(submission.attempt)

        #expect(submission.error == .rateLimited)
        #expect(!submission.isPending)
        #expect(await recovery.saves.isEmpty)
    }

    @Test
    func `Back before the task starts prevents preparation and allows a fresh presentation`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts)
        let submission = ImportWalletModel(coordinator: coordinator)
        submission.present()
        submission.submit(Self.phrase, passphrase: "TREZOR")
        let attempt = try #require(submission.attempt)
        submission.isPresented = false
        await submission.run(attempt)
        #expect(coordinator.recovery == nil)
        #expect(await recovery.saves.isEmpty)
        #expect(!submission.isPending)
        submission.present()
        #expect(submission.isPresented)
        #expect(submission.attempt == nil)
    }
}
