import SwiftUI

/// Shows RPC in a navigation stack.
struct RPCScene: View {
    @Bindable var coordinator: RPCCoordinator

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            RPCScreen(coordinator: coordinator)
                .navigationDestination(for: RPCRoute.self) {
                    RPCDestination(coordinator: coordinator, route: $0)
                }
        }
    }
}
