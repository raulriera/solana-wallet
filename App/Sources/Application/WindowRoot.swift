import RPC
import SwiftUI

/// Owns one window: its network, its workflows, its appearance lifecycle, and the resumption of pending transactions'
/// watches.
///
/// The window keeps its network with its scene state and creates its workflows when it first appears, so a root value
/// that SwiftUI discards creates no coordinator or network service.
struct WindowRoot: View {
    @SceneStorage("window.network") private var network = Network.mainnet
    @State private var window: WindowModel?
    let services: AppServices

    var body: some View {
        ZStack {
            if let window {
                WindowContent(window: window, network: $network, services: services)
            } else {
                // The services stay the same for the app's lifetime, and a later network change replaces only the
                // portfolio, so the window creates its workflows once, when it appears.
                Color.clear
                    .onAppear { window = WindowModel(services: services, network: network) }
            }
        }
        .windowAppearance(services: services.appearance)
        .limitedTextSize()
        .environment(\.artworkColors, services.artworkColors)
        .environment(services.currencyStore)
        .environment(services.contactStore)
        .environment(services.accountStore)
        .environment(\.accountCreation, services.accountCreation)
        .transactionResumption(providerRevisions: services.providerRevisions)
        .environment(services.transactionStore)
        .environment(\.network, network)
    }
}
