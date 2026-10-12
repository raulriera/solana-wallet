import SwiftUI

/// Owns Providers' navigation container; the flow decides what's pushed.
struct ProvidersScene: View {
    @Bindable var flow: ProvidersFlow

    var body: some View {
        NavigationStack(path: $flow.path) {
            ProvidersScreen(flow: flow)
                .navigationDestination(for: ProvidersRoute.self) { route in
                    switch route {
                    case .customRPCSetup:
                        if let setup = flow.setup {
                            ProviderSetupScreen(purpose: .customRPC, submission: setup)
                                .providerSetupLifecycle(setup, closesWhenSaved: true)
                        }
                    case .providerDetails:
                        ProviderDetailsScreen(keyPreview: flow.keyPreview, actions: flow)
                    case .providerKey(let purpose):
                        if let newKey = flow.newKey {
                            ProviderSetupScreen(purpose: purpose, submission: newKey)
                                .providerSetupLifecycle(newKey, closesWhenSaved: true)
                        }
                    case .customRPCDetails:
                        if let url = flow.details {
                            CustomRPCDetailsScreen(url: url, isListed: flow.customRPCs.contains(url),
                                                   removal: $flow.removal)
                        }
                    }
                }
        }
    }
}
