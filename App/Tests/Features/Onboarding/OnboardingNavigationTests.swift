import Foundation
import Testing
import Wallet
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct OnboardingNavigationTests {
    @Test
    func `Back from phrase entry ends an in-flight import before task cancellation`() async throws {
        let gate = Suspension()
        let recovery = OnboardingRecoveryStore()
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery(gate: gate).client),
                                                wallet: Wallet(), recovery: recovery, accounts: accounts)
        let submission = ImportWalletModel(coordinator: coordinator)
        let navigation = OnboardingNavigation(walletImport: submission, providers: .inMemory(.inMemory()))
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

    @Test
    func `The provider choice's screens show above onboarding's steps`() throws {
        let providers = ProvidersCoordinator.inMemory(.inMemory())
        let navigation = OnboardingNavigation(walletImport: Self.submission(), providers: providers)
        navigation.path = [.recovery, .providers]

        providers.addCustomRPC()
        try #require(navigation.stack == [.recovery, .providers, .providersRoute(.customRPCSetup)])
        navigation.stack.removeLast()

        #expect(providers.path.isEmpty)
        #expect(navigation.path == [.recovery, .providers])
        #expect(navigation.stack == [.recovery, .providers])
    }

    @Test(arguments: [OnboardingStep.providers, .providersRoute(.customRPCSetup), .providersRoute(.providerDetails)])
    func `The provider choice's screens are the last step`(step: OnboardingStep) {
        #expect(step.number == OnboardingStep.total)
    }

    private static func submission() -> ImportWalletModel {
        let recovery = OnboardingRecoveryStore()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client),
                                                wallet: Wallet(), recovery: recovery,
                                                accounts: AccountStore.inMemory())
        return ImportWalletModel(coordinator: coordinator)
    }
}
