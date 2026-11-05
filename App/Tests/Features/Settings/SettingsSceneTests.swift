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
        let rpcStore = RPCStore.inMemory(selection: .helius)
        let first = RPCCoordinator.inMemory(rpcStore)
        let settings = AppearanceSettingsModel(
            appearance: AppearanceCoordinator(store: AppearanceStore(directory: fixture.directory), recovery: nil),
            catalog: ThemeCatalog(directory: fixture.directory), packages: PackService()
        )
        let wallet = try await PublicWalletAccounts()
        let rendered = AsyncStream<Int>.makeStream()
        let hosted = try HostedWindow(SettingsSceneRoot(
            scene: SettingsScene(settings: settings, account: .constant(wallet.first), network: .constant(.mainnet),
                                 security: makeSecurity(), rpcCoordinator: first),
            generation: 0, rendered: rendered.continuation, rpcStore: rpcStore, wallet: wallet))
        defer {
            hosted.close()
            rendered.continuation.finish()
        }
        var renders = rendered.stream.makeAsyncIterator()
        try #require(await renders.next() == 0)

        let second = RPCCoordinator.inMemory(rpcStore)
        hosted.host.rootView = SettingsSceneRoot(
            scene: SettingsScene(settings: settings, account: .constant(wallet.first), network: .constant(.mainnet),
                                 security: makeSecurity(), rpcCoordinator: second),
            generation: 1, rendered: rendered.continuation, rpcStore: rpcStore, wallet: wallet)
        try #require(await renders.next() == 1)
        first.select(.solana)

        for await attempt in Observations({ first.attempt }) where attempt == nil { break }
        #expect(rpcStore.settings?.selection == .solana)
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
    let rpcStore: RPCStore
    let wallet: PublicWalletAccounts

    var body: some View {
        scene
            .environment(rpcStore)
            .environment(wallet)
            .onChange(of: generation, initial: true) {
                rendered.yield(generation)
            }
    }
}
