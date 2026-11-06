import RPC
import SwiftUI

/// The root view of one window, which injects the shared stores and appearance.
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
                Color.clear
                    .task {
                        await services.rpcStore.load()
                        guard !Task.isCancelled else { return }
                        window = WindowModel(accounts: services.accountStore)
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
        .environment(services.privateBalanceStore)
        .environment(services.rpcStore)
        .environment(services.priceStore)
        .environment(services.transactionStore)
    }
}
