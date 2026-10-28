import Observation
import RPC
import SwiftUI
import Testing
import Themes
@testable import widgets

/// Runs the Settings tab in a real window, so its workflows live as long as SwiftUI keeps the tab.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SettingsSceneTests {
    /// The window creates new workflows each time it shows the tab again; the tab's lifecycle keeps running the changes
    /// of the first ones, so a choice made before the window updated still saves.
    /// - Throws: A test prerequisite error.
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
        let account = try Account.fixture(index: 0)
        let rendered = AsyncStream<Int>.makeStream()
        let hosted = try HostedWindow(SettingsSceneRoot(
            scene: SettingsScene(settings: settings, account: account, network: .constant(.mainnet),
                                 security: makeSecurity(), providers: first),
            generation: 0, rendered: rendered.continuation, providers: providerStore))
        defer {
            hosted.close()
            rendered.continuation.finish()
        }
        var renders = rendered.stream.makeAsyncIterator()
        try #require(await renders.next() == 0)

        let second = ProvidersCoordinator.inMemory(providerStore)
        hosted.host.rootView = SettingsSceneRoot(
            scene: SettingsScene(settings: settings, account: account, network: .constant(.mainnet),
                                 security: makeSecurity(), providers: second),
            generation: 1, rendered: rendered.continuation, providers: providerStore)
        try #require(await renders.next() == 1)
        first.select(.solana)

        // The suite's time limit ends the wait if the tab never runs the first workflow's change.
        for await attempt in Observations({ first.attempt }) where attempt == nil { break }
        #expect(providerStore.settings?.selection == .solana)
    }

    /// Creates Security & Privacy steps that never read recovery or reset anything.
    /// - Returns: A coordinator with an empty path.
    private func makeSecurity() -> SecurityCoordinator {
        SecurityCoordinator(services: SecurityServices(
            recovery: RecoveryReveal(store: SecurityRecoveryStore()),
            owner: TestOwner(),
            reset: AppReset(storage: ResetStorage(), revision: Revision()),
            pasteboard: NoPasteboard()
        ))
    }
}

/// Hosts the Settings tab as a window does and reports each completed update.
private struct SettingsSceneRoot: View {
    let scene: SettingsScene
    let generation: Int
    let rendered: AsyncStream<Int>.Continuation
    /// The shared provider settings, which a window's root supplies.
    let providers: ProviderStore

    var body: some View {
        scene
            .environment(providers)
            .onChange(of: generation, initial: true) {
                rendered.yield(generation)
            }
    }
}
