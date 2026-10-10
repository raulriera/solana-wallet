import Foundation
import RPC
import Testing
import Vault
import Wallet
@testable import widgets

/// Exercises presentation orchestration with public fixtures and isolated existing stores.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ImportSubmissionTests {
    private static let phrase = OnboardingCoordinatorTests.phrase

    /// Submission preserves the original passphrase and commits only once despite repeated taps/tasks,
    /// and the screen sees the import in flight so it can lock its input until the import ends.
    @Test
    func `Repeated submission and task evaluation complete one accepted import`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        let submission = ImportSubmission(coordinator: coordinator)
        let screen: any ImportSubmitting = submission
        submission.present()
        screen.submit(Self.phrase, passphrase: " TrEzOr ")
        let attempt = try #require(submission.attempt)
        screen.submit(Self.phrase, passphrase: "different")
        #expect(submission.attempt == attempt)
        #expect(screen.isPending)
        #expect(await recovery.saves.isEmpty)

        await submission.run(attempt)
        await submission.run(attempt)
        screen.submit(Self.phrase, passphrase: "different")
        #expect(submission.attempt == nil)

        let account = try #require(coordinator.account)
        let saved = try await recovery.recovery(for: account.recoveryID, reason: "Read public test fixture")
        #expect(saved.passphrase == " TrEzOr ")
        #expect(router.destination == .onboarding)
        #expect(await recovery.saves.count == 1)
        #expect(await accounts.additions.count == 1)
        #expect(!screen.isPending)
        #expect(submission.error == nil)
    }

    /// An explicit retry reuses the prepared account even when phrase spacing changes.
    @Test
    func `Persistence retry keeps the draft identity and skips committed recovery`() async throws {
        let http = HTTPResponses.discovery(fundedOffsets: [1])
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery, firstError: OnboardingCoordinatorError.accountStorageFailed)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        let submission = ImportSubmission(coordinator: coordinator)
        submission.present()
        submission.submit(Self.phrase, passphrase: "TREZOR")
        await submission.run(submission.attempt)
        #expect(submission.error == .saveFailed)
        #expect(router.destination == .onboarding)
        let firstAccount = try #require(await accounts.additions.first)

        submission.submit("  " + Self.phrase.replacingOccurrences(of: " ", with: "\n") + "  ", passphrase: "TREZOR")
        #expect(submission.error == nil)
        await submission.run(submission.attempt)

        #expect(coordinator.account?.id == firstAccount.id)
        #expect(await recovery.saves == [firstAccount.recoveryID])
        #expect(await accounts.records.count == 1)
        #expect(coordinator.account?.path == firstAccount.path)
        #expect(firstAccount.path.description == "m/44'/501'/0'")
        #expect(await http.requests.count == 1)
    }

    /// Changed passphrase input explicitly starts another draft without deleting committed recovery.
    /// - Parameter passphrase: A case or whitespace change that must not be normalized away.
    @Test(arguments: ["trezor", " TREZOR "])
    func `Changed input starts a new import while retaining previously saved recovery`(passphrase: String) async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery, firstError: OnboardingCoordinatorError.accountStorageFailed)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        let submission = ImportSubmission(coordinator: coordinator)
        submission.present()
        submission.submit(Self.phrase, passphrase: "TREZOR")
        await submission.run(submission.attempt)
        let original = try #require(await accounts.additions.first)

        submission.submit(Self.phrase, passphrase: passphrase)
        await submission.run(submission.attempt)

        let imported = try #require(coordinator.account)
        #expect(imported.id != original.id)
        #expect(imported.recoveryID != original.recoveryID)
        #expect(await recovery.contains(original.recoveryID))
        #expect(await recovery.contains(imported.recoveryID))
        let saved = try await recovery.recovery(for: imported.recoveryID, reason: "Read public test fixture")
        #expect(saved.passphrase == passphrase)
    }

    /// Preparation failures release the attempt, permit retry, and never expose underlying details.
    @Test
    func `Preparation failure permits another explicit attempt without saving anything`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let wallet = OnboardingWallet(error: NSError(domain: "private-marker", code: 1))
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: wallet, recovery: recovery, accounts: accounts, router: router)
        let submission = ImportSubmission(coordinator: coordinator)
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
        #expect(await accounts.additions.isEmpty)
    }

    /// A rate-limited account lookup says so, so the person waits before trying again.
    @Test
    func `A rate-limited account lookup explains the limit`() async {
        let http = HTTPResponses.discovery(error: .http(statusCode: 429, retryAfter: "3"))
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: http.client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        let submission = ImportSubmission(coordinator: coordinator)
        submission.present()
        submission.submit(Self.phrase, passphrase: "TREZOR")

        await submission.run(submission.attempt)

        #expect(submission.error == .rateLimited)
        #expect(!submission.isPending)
        #expect(await recovery.saves.isEmpty)
    }

    /// Leaving before SwiftUI starts its task invalidates the queued secret-bearing request.
    @Test
    func `Back before the task starts prevents preparation and allows a fresh presentation`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client), wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        let submission = ImportSubmission(coordinator: coordinator)
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
