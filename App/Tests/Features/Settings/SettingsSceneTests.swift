import Observation
import RPC
import Storage
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
        let settings = makeSettings(in: fixture)
        let wallet = try await ThrowawayWalletAccounts()
        let rendered = AsyncStream<Int>.makeStream()
        let hosted = try HostedWindow(SettingsSceneRoot(
            scene: SettingsScene(settings: settings, account: .constant(wallet.first), network: .constant(.mainnet),
                                 security: makeSecurity(), rpcCoordinator: first, pricesCoordinator: .inMemory()),
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
                                 security: makeSecurity(), rpcCoordinator: second, pricesCoordinator: .inMemory()),
            generation: 1, rendered: rendered.continuation, rpcStore: rpcStore, wallet: wallet)
        try #require(await renders.next() == 1)
        first.select(.solana)

        for await attempt in Observations({ first.attempt }) where attempt == nil { break }
        #expect(rpcStore.settings?.selection == .solana)
    }

    @Test
    func `RPC and Prices read errors show their alerts`() async throws {
        let rpc = RPCCoordinator.inMemory(.inMemory(StoredValue(failsLoading: true)))
        let prices = PricesCoordinator.inMemory(.inMemory(StoredValue(failsLoading: true)))

        #expect(try await presentsAlert(rpc: rpc, prices: .inMemory()))
        #expect(rpc.error == .selectionUnreadable)
        #expect(try await presentsAlert(rpc: .inMemory(.inMemory()), prices: prices))
        #expect(prices.error == .settingsUnreadable)
    }

    private func presentsAlert(rpc: RPCCoordinator, prices: PricesCoordinator) async throws -> Bool {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let wallet = try await ThrowawayWalletAccounts()
        let rendered = AsyncStream<Int>.makeStream()
        let hosted = try HostedWindow(SettingsSceneRoot(
            scene: SettingsScene(settings: makeSettings(in: fixture), account: .constant(wallet.first),
                                 network: .constant(.mainnet), security: makeSecurity(), rpcCoordinator: rpc,
                                 pricesCoordinator: prices),
            generation: 0, rendered: rendered.continuation, rpcStore: .inMemory(), wallet: wallet))
        defer {
            hosted.close()
            rendered.continuation.finish()
        }
        return try await hosted.presentsViewController()
    }

    private func makeSettings(in fixture: CatalogFixture) -> AppearanceSettingsModel {
        AppearanceSettingsModel(
            appearance: AppearanceCoordinator(store: AppearanceStore(directory: fixture.directory), recovery: nil),
            catalog: ThemeCatalog(directory: fixture.directory), packages: PackService()
        )
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
    let wallet: ThrowawayWalletAccounts

    var body: some View {
        scene
            .environment(rpcStore)
            .environment(wallet)
            .onChange(of: generation, initial: true) {
                rendered.yield(generation)
            }
    }
}
