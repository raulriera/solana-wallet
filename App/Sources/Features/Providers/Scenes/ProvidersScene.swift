import SwiftUI

/// Owns Providers' navigation container; the coordinator decides what's pushed.
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
