import SwiftUI

/// Shows Providers in a navigation stack.
struct ProvidersScene: View {
    @Bindable var coordinator: ProvidersCoordinator

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            ProvidersScreen(coordinator: coordinator)
                .navigationDestination(for: ProvidersRoute.self) {
                    ProvidersDestination(coordinator: coordinator, route: $0)
                }
        }
    }
}
