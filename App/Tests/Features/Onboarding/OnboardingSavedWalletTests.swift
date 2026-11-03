import Observation
import SwiftUI
import Testing
import Wallet
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct OnboardingSavedWalletTests {
    @Test
    func `A welcome window opens the wallet that another window saves`() async throws {
        let accounts = AccountStore.inMemory()
        await accounts.load()
        let providerStore = ProviderStore.inMemory()
        let coordinator = OnboardingCoordinator(discovery: AccountDiscovery(rpc: HTTPResponses.discovery().client),
                                                wallet: Wallet(), recovery: OnboardingRecoveryStore(),
                                                accounts: accounts)
        let window = OpenedAccount()
        let scene = OnboardingScene(account: Bindable(window).account, coordinator: coordinator,
                                    providers: .inMemory(providerStore), pasteboard: NoPasteboard())
        let hosted = try HostedWindow(scene.environment(providerStore))
        defer { hosted.close() }
        try #require(try await hosted.appears())
        let saved = try widgets.Account.fixture(index: 1)

        try await accounts.add(saved)

        for await opened in Observations({ window.account }) where opened?.id == saved.id { break }
        #expect(coordinator.account == nil)
    }
}
