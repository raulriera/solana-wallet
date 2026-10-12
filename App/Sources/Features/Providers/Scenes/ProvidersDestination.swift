import SwiftUI

/// Shows a screen that Providers pushes, in Settings and in onboarding; the flow decides what each screen shows.
struct ProvidersDestination: View {
    @Bindable var flow: ProvidersFlow
    let route: ProvidersRoute

    var body: some View {
        switch route {
        case .customRPCSetup:
            if let setup = flow.setup {
                ProviderSetupScreen(purpose: .customRPC, submission: setup)
                    .providerSetupLifecycle(setup)
            }
        case .providerDetails:
            ProviderDetailsScreen(keyPreview: flow.keyPreview, actions: flow)
        case .providerKey(let purpose):
            if let newKey = flow.newKey {
                ProviderSetupScreen(purpose: purpose, submission: newKey)
                    .providerSetupLifecycle(newKey)
            }
        case .customRPCDetails:
            if let url = flow.details {
                CustomRPCDetailsScreen(url: url, isListed: flow.customRPCs.contains(url), removal: $flow.removal)
            }
        }
    }
}
