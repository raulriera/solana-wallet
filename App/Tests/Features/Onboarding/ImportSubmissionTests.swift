import Foundation
import Testing
import Vault
import Wallet
@testable import widgets

/// Exercises presentation orchestration with public fixtures and isolated existing stores.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ImportSubmissionTests {
    private static let phrase = OnboardingCoordinatorTests.phrase

    /// Submission preserves the original passphrase and commits only once despite repeated taps/tasks.
    @Test
    func `Repeated submission and task evaluation complete one accepted import`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        let submission = ImportSubmission(coordinator: coordinator)
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
        #expect(router.destination == .wallet(accountID: account.id))
        #expect(await recovery.saves.count == 1)
        #expect(await accounts.additions.count == 1)
        #expect(!submission.isPending)
        #expect(submission.failure == nil)
    }

    /// An explicit retry reuses the prepared account even when phrase spacing changes.
    @Test
    func `Persistence retry keeps the draft identity and skips committed recovery`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery, firstFailure: OnboardingCoordinatorError.accountStorageFailed)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        let submission = ImportSubmission(coordinator: coordinator)
        submission.present()
        submission.submit(Self.phrase, passphrase: "TREZOR")
        await submission.run(submission.attempt)
        #expect(submission.failure != nil)
        #expect(router.destination == .onboarding)
        let firstAccount = try #require(await accounts.additions.first)

        submission.submit("  " + Self.phrase.replacingOccurrences(of: " ", with: "\n") + "  ", passphrase: "TREZOR")
        #expect(submission.failure == nil)
        await submission.run(submission.attempt)

        #expect(coordinator.account?.id == firstAccount.id)
        #expect(await recovery.saves == [firstAccount.recoveryID])
        #expect(await accounts.records.count == 1)
    }

    /// Changed passphrase input explicitly starts another draft without deleting committed recovery.
    /// - Parameter passphrase: A case or whitespace change that must not be normalized away.
    @Test(arguments: ["trezor", " TREZOR "])
    func `Changed input starts a new import while retaining previously saved recovery`(passphrase: String) async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery, firstFailure: OnboardingCoordinatorError.accountStorageFailed)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
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
        let wallet = OnboardingWallet(failure: NSError(domain: "private-marker", code: 1))
        let coordinator = OnboardingCoordinator(wallet: wallet, recovery: recovery, accounts: accounts, router: router)
        let submission = ImportSubmission(coordinator: coordinator)
        submission.present()
        submission.submit(Self.phrase, passphrase: "TREZOR")
        let attempt = try #require(submission.attempt)
        await submission.run(attempt)
        #expect(submission.failure != nil)
        #expect(submission.failure?.contains("private-marker") == false)
        #expect(!submission.isPending)
        #expect(coordinator.recovery == nil)

        submission.submit(Self.phrase, passphrase: "TREZOR")
        #expect(submission.attempt != nil)
        #expect(submission.attempt != attempt)
        #expect(submission.failure == nil)
        await submission.run(submission.attempt)
        #expect(await recovery.saves.isEmpty)
        #expect(await accounts.additions.isEmpty)
    }

    /// Leaving before SwiftUI starts its task invalidates the queued secret-bearing request.
    @Test
    func `Back before the task starts prevents preparation and allows a fresh presentation`() async throws {
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
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
