import SwiftUI

/// Lists the price providers with a checkmark on the one in use.
struct PricesScreen: View {
    @Environment(PriceStore.self) private var prices
    let coordinator: PricesCoordinator

    var body: some View {
        let settings = prices.settings
        let customServers = settings?.customServers ?? []
        Form {
            Section {
                TitleCardContent(
                    title: "Prices",
                    message: "Your wallets get token prices directly from the price provider you choose.",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
            }

            PriceSelectionSection(selection: settings?.selection, customServers: customServers, actions: coordinator)
        }
        .formStyle(.choices(checkmark: .leading))
        .animation(.default, value: customServers.count)
        .navigationTitle("Prices")
        .toolbarTitleDisplayMode(.inline)
    }
}
