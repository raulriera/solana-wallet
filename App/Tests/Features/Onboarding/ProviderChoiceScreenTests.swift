import Observation
import SwiftUI
import Testing
import Wallet
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProviderChoiceScreenTests {
    @Test
    func `A key entered to choose Helius opens the saved wallet`() async throws {
        let recovery = OnboardingRecoveryStore()
        let settings = StoredValue(ProviderSettings(selection: .solana))
        let providerStore = ProviderStore.inMemory(settings)
        let providers = ProvidersCoordinator.inMemory(providerStore)
        let accounts = AccountStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client),
                                                wallet: Wallet(), recovery: recovery, accounts: accounts)
        let window = OpenedAccount()
        let scene = OnboardingScene(account: Bindable(window).account, coordinator: coordinator, providers: providers,
                                    pasteboard: NoPasteboard())
        let hosted = try HostedWindow(scene.environment(providerStore))
        defer { hosted.close() }
        try #require(try await hosted.appears())
        try await coordinator.create()
        let account = try await coordinator.complete()
        providers.select(.helius)
        try #require(try await hosted.presentsViewController())
        #expect(accounts.accounts.map(\.id) == [account.id])
        #expect(window.account == nil)
        let keyEntry = try #require(providers.keyEntry)

        keyEntry.submit("fixture-key")

        for await opened in Observations({ window.account }) where opened == account { break }
        #expect(hosted.host.presentedViewController == nil)
        #expect(await settings.value?.selection == .helius)
    }
}
