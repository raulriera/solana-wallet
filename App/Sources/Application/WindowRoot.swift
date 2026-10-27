import RPC
import SwiftUI

/// Owns one window: its network, its workflows, its appearance lifecycle, the shared stores it injects, and the
/// resumption of pending transactions' watches.
///
/// The window keeps its network with its scene state and creates its workflows when it first appears, so a root value
/// that SwiftUI discards creates no coordinator or network service. It reads the provider settings first, so work keyed
/// on the provider connection starts once instead of again when the read ends.
struct WindowRoot: View {
    @SceneStorage("window.network") private var network = Network.mainnet
    @State private var window: WindowModel?
    let services: AppServices

    var body: some View {
        ZStack {
            if let window {
                WindowContent(window: window, network: $network, services: services)
                    .transactionResumption()
            } else {
                // The services stay the same for the app's lifetime, and a later network change replaces only the
                // portfolio, so the window creates its workflows once, when it appears. Settings that can't be read
                // still open the window, whose requests then explain the failure.
                Color.clear
                    .task {
                        await services.providerStore.load()
                        // A window that closed during the read creates no workflows.
                        guard !Task.isCancelled else { return }
                        window = WindowModel(services: services, network: network)
                    }
            }
        }
        .windowAppearance(services: services.appearance)
        .limitedTextSize()
        .environment(\.artworkColors, services.artworkColors)
        .environment(services.currencyStore)
        .environment(services.contactStore)
        .environment(services.accountStore)
        .environment(\.accountCreation, services.accountCreation)
        .environment(services.portfolios)
        .environment(services.providerStore)
        .environment(services.transactionStore)
        .environment(\.network, network)
    }
}
