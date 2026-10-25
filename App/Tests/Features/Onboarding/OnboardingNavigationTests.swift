import Foundation
import Testing
import Wallet
@testable import widgets

/// Verifies that onboarding's navigation path is the single signal that ends phrase entry, and that the provider choice's
/// screens show above onboarding's steps.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct OnboardingNavigationTests {
    /// Back pops phrase entry from the path, which invalidates its attempt before SwiftUI cancels the task.
    @Test
    func `Back from phrase entry ends an in-flight import before task cancellation`() async throws {
        let gate = Suspension()
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let router = WindowRouter(initialDestination: .onboarding)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery(gate: gate).client),
                                                wallet: Wallet(), recovery: recovery, accounts: accounts, router: router)
        let submission = ImportWalletModel(coordinator: coordinator)
        let navigation = OnboardingNavigation(walletImport: submission, providers: .inMemory(settings: StoredValue(), providerKey: StoredValue()))
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
        #expect(accounts.accounts.isEmpty)
    }

    /// The provider choice's pushed screens show above onboarding's steps, and Back from them leaves those steps.
    /// - Throws: A test prerequisite error.
    @Test
    func `The provider choice's screens show above onboarding's steps`() throws {
        let providers = ProvidersCoordinator.inMemory(settings: StoredValue(), providerKey: StoredValue())
        let navigation = OnboardingNavigation(walletImport: Self.submission(), providers: providers)
        navigation.path = [.recovery, .providers]

        providers.addCustomRPC()
        try #require(navigation.stack == [.recovery, .providers, .providersRoute(.customRPCSetup)])
        navigation.stack.removeLast()

        #expect(providers.path.isEmpty)
        #expect(navigation.path == [.recovery, .providers])
        #expect(navigation.stack == [.recovery, .providers])
    }

    /// Every screen of the provider choice counts as onboarding's last step.
    /// - Parameter step: A screen of the provider choice.
    @Test(arguments: [OnboardingStep.providers, .providersRoute(.customRPCSetup), .providersRoute(.providerDetails)])
    func `The provider choice's screens are the last step`(step: OnboardingStep) {
        #expect(step.number == OnboardingStep.total)
    }

    /// Creates an import submission whose coordinator never reaches the network or device storage.
    /// - Returns: A submission for navigation that never imports.
    private static func submission() -> ImportWalletModel {
        let recovery = OnboardingRecoveryStore()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client),
                                                wallet: Wallet(), recovery: recovery,
                                                accounts: AccountStore.inMemory(),
                                                router: WindowRouter(initialDestination: .onboarding))
        return ImportWalletModel(coordinator: coordinator)
    }
}
