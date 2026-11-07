import SwiftUI

/// Shows a screen that Prices pushes.
struct PricesDestination: View {
    @Environment(PriceStore.self) private var prices
    let coordinator: PricesCoordinator
    let route: PricesRoute

    var body: some View {
        switch route {
        case .serverSetup:
            if let setup = coordinator.setup {
                PriceServerSetupScreen(submission: setup)
                    .providerSetupLifecycle()
            }
        case .serverDetails:
            if let url = coordinator.details {
                PriceServerDetailsScreen(url: url, isListed: prices.settings?.customServers.contains(url) == true,
                                         isSelected: prices.settings?.selection == .custom(url),
                                         actions: coordinator)
            }
        }
    }
}
