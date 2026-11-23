import SwiftUI

/// Shows the RPC provider choice, with a button that opens the new wallet.
struct RPCChoiceScreen: View {
    let coordinator: RPCCoordinator
    /// The action that opens the saved wallet.
    let continueSetup: () -> Void

    var body: some View {
        RPCScreen(coordinator: coordinator) {
            Section {
                Button("Continue", action: continueSetup)
            }
        }
        .onChange(of: coordinator.completedKeyChoice) { _, choice in
            if choice != nil { continueSetup() }
        }
    }
}
