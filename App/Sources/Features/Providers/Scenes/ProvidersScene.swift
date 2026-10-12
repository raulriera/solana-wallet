import SwiftUI

/// Owns Providers' navigation container; the flow decides what's pushed.
struct ProvidersScene: View {
    @Bindable var flow: ProvidersFlow

    var body: some View {
        NavigationStack(path: $flow.path) {
            ProvidersScreen(flow: flow)
                .navigationDestination(for: ProvidersRoute.self) { ProvidersDestination(flow: flow, route: $0) }
        }
    }
}
