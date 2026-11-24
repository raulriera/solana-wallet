import SwiftUI

/// Shows a screen that RPC pushes.
struct RPCDestination: View {
    @Environment(RPCStore.self) private var rpcStore
    let coordinator: RPCCoordinator
    let route: RPCRoute

    var body: some View {
        switch route {
        case .customRPCSetup:
            if let setup = coordinator.setup {
                RPCSetupScreen(purpose: .customRPC, submission: setup)
                    .providerSetupLifecycle()
            }
        case .apiKeyDetails:
            APIKeyDetailsScreen(keyPreview: rpcStore.keyPreview, actions: coordinator)
        case .apiKey(let purpose):
            if let newKey = coordinator.newKey {
                RPCSetupScreen(purpose: purpose, submission: newKey)
                    .providerSetupLifecycle()
            }
        case .customRPCDetails:
            if let url = coordinator.details {
                CustomRPCDetailsScreen(url: url, isListed: rpcStore.settings?.customRPC(for: url) != nil,
                                       isSelected: rpcStore.settings?.selection == .custom(url),
                                       actions: coordinator)
            }
        }
    }
}
