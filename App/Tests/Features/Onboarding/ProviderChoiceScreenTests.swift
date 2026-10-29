import Observation
import SwiftUI
import Testing
import Wallet
@testable import widgets

/// Runs onboarding's provider choice in a real window, so key entry continues setup as it does on screen.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProviderChoiceScreenTests {
    /// Choosing Helius without a key opens key entry; the saved key closes the sheet, then chooses Helius and opens the
    /// saved wallet, so the sheet never slides away while onboarding fades out.
    /// - Throws: A test prerequisite error.
    @Test
    func `A key entered to choose Helius opens the saved wallet`() async throws {
        let recovery = OnboardingRecoveryStore()
        let settings = StoredValue(ProviderSettings(selection: .solana))
        let providerStore = ProviderStore.inMemory(settings)
        let providers = ProvidersCoordinator.inMemory(providerStore)
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client),
                                                wallet: Wallet(), recovery: recovery,
                                                accounts: AccountStore.inMemory())
        let window = OpenedAccount()
        let scene = OnboardingScene(account: Bindable(window).account, coordinator: coordinator, providers: providers,
                                    pasteboard: NoPasteboard())
        let hosted = try HostedWindow(scene.environment(providerStore))
        defer { hosted.close() }
        try #require(try await hosted.appears())
        // Saving the wallet on screen pushes the provider choice.
        try await coordinator.create()
        let account = try await coordinator.complete()
        providers.select(.helius)
        try #require(try await hosted.presentsViewController())
        let keyEntry = try #require(providers.keyEntry)

        keyEntry.submit("fixture-key")

        // The suite's time limit ends the wait if the wallet never opens.
        for await opened in Observations({ window.account }) where opened == account { break }
        // UIKit keeps the presented sheet until it has finished closing.
        #expect(hosted.host.presentedViewController == nil)
        #expect(await settings.value?.selection == .helius)
    }
}

/// Holds the account that a hosted onboarding window shows, in place of the window's model.
@MainActor
@Observable
private final class OpenedAccount {
    /// The account that onboarding opens, or `nil` until it finishes.
    var account: widgets.Account?
}
