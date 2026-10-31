import Observation
import RPC
import SwiftUI
import Testing
import Themes
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SettingsSceneTests {
    @Test
    func `The tab runs its first workflows' changes after the window shows it again`() async throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let providerStore = ProviderStore.inMemory(selection: .helius)
        let first = ProvidersCoordinator.inMemory(providerStore)
        let settings = AppearanceSettingsModel(
            appearance: AppearanceCoordinator(store: AppearanceStore(directory: fixture.directory), recovery: nil),
            catalog: ThemeCatalog(directory: fixture.directory), packages: PackService()
        )
        let wallet = try await PublicWalletAccounts()
        let rendered = AsyncStream<Int>.makeStream()
        let hosted = try HostedWindow(SettingsSceneRoot(
            scene: SettingsScene(settings: settings, account: .constant(wallet.first), network: .constant(.mainnet),
                                 security: makeSecurity(), providers: first),
            generation: 0, rendered: rendered.continuation, providers: providerStore, wallet: wallet))
        defer {
            hosted.close()
            rendered.continuation.finish()
        }
        var renders = rendered.stream.makeAsyncIterator()
        try #require(await renders.next() == 0)

        let second = ProvidersCoordinator.inMemory(providerStore)
        hosted.host.rootView = SettingsSceneRoot(
            scene: SettingsScene(settings: settings, account: .constant(wallet.first), network: .constant(.mainnet),
                                 security: makeSecurity(), providers: second),
            generation: 1, rendered: rendered.continuation, providers: providerStore, wallet: wallet)
        try #require(await renders.next() == 1)
        first.select(.solana)

        for await attempt in Observations({ first.attempt }) where attempt == nil { break }
        #expect(providerStore.settings?.selection == .solana)
    }

    private func makeSecurity() -> SecurityCoordinator {
        SecurityCoordinator(services: SecurityServices(
            recovery: RecoveryReveal(store: SecurityRecoveryStore()),
            owner: TestOwner(),
            reset: AppReset(storage: ResetStorage()),
            pasteboard: NoPasteboard()
        ))
    }
}

private struct SettingsSceneRoot: View {
    let scene: SettingsScene
    let generation: Int
    let rendered: AsyncStream<Int>.Continuation
    let providers: ProviderStore
    let wallet: PublicWalletAccounts

    var body: some View {
        scene
            .environment(providers)
            .environment(wallet)
            .onChange(of: generation, initial: true) {
                rendered.yield(generation)
            }
    }
}
