import SwiftUI

/// Shows a screen that Providers pushes.
struct ProvidersDestination: View {
    @Environment(ProviderStore.self) private var providers
    @Bindable var coordinator: ProvidersCoordinator
    let route: ProvidersRoute

    var body: some View {
        switch route {
        case .customRPCSetup:
            if let setup = coordinator.setup {
                ProviderSetupScreen(purpose: .customRPC, submission: setup)
                    .providerSetupLifecycle()
            }
        case .providerDetails:
            ProviderDetailsScreen(keyPreview: providers.keyPreview, actions: coordinator)
        case .providerKey(let purpose):
            if let newKey = coordinator.newKey {
                ProviderSetupScreen(purpose: purpose, submission: newKey)
                    .providerSetupLifecycle()
            }
        case .customRPCDetails:
            if let url = coordinator.details {
                CustomRPCDetailsScreen(url: url, isListed: providers.settings?.customRPCs.contains(url) == true,
                                       removal: $coordinator.removal, actions: coordinator)
            }
        }
    }
}
