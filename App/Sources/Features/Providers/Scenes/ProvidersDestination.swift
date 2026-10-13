import SwiftUI

/// Shows a screen that Providers pushes, in Settings and in onboarding; the coordinator decides what each screen shows.
struct ProvidersDestination: View {
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
            ProviderDetailsScreen(keyPreview: coordinator.keyPreview, actions: coordinator)
        case .providerKey(let purpose):
            if let newKey = coordinator.newKey {
                ProviderSetupScreen(purpose: purpose, submission: newKey)
                    .providerSetupLifecycle()
            }
        case .customRPCDetails:
            if let url = coordinator.details {
                CustomRPCDetailsScreen(url: url, isListed: coordinator.customRPCs.contains(url),
                                       removal: $coordinator.removal)
            }
        }
    }
}
