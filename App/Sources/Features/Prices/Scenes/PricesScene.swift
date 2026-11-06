import SwiftUI

/// Shows Prices in a navigation stack.
struct PricesScene: View {
    @Bindable var coordinator: PricesCoordinator

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            PricesScreen(coordinator: coordinator)
                .navigationDestination(for: PricesRoute.self) {
                    PricesDestination(coordinator: coordinator, route: $0)
                }
        }
    }
}
