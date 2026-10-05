import Foundation
import Testing
import Wallet
@testable import widgets

/// Verifies that onboarding's navigation path is the single signal that ends phrase entry.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct OnboardingNavigationTests {
    /// Back pops phrase entry from the path, which invalidates its attempt before SwiftUI cancels the task.
    @Test
    func `Back from phrase entry ends an in-flight import before task cancellation`() async throws {
        let gate = Suspension()
        let recovery = OnboardingRecoveryStore()
        let accounts = OnboardingAccountStore(recovery: recovery)
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery(gate: gate).client),
                                                wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        let submission = ImportSubmission(coordinator: coordinator)
        let navigation = OnboardingNavigation(importSubmission: submission)
        navigation.showImport()
        try #require(navigation.path == [.importWallet])
        submission.submit(OnboardingCoordinatorTests.phrase, passphrase: "TREZOR")
        let attempt = try #require(submission.attempt)
        let operation = Task { await submission.run(attempt) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        navigation.path = []
        #expect(!submission.isPresented)
        gate.resume()
        await operation.value

        #expect(coordinator.recovery == nil)
        #expect(coordinator.account == nil)
        #expect(await recovery.saves.isEmpty)
        #expect(await accounts.additions.isEmpty)
    }
}
