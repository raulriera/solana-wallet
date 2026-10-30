import SwiftUI

/// Shows the RPC provider choice, with a button that opens the new wallet.
struct ProviderChoiceScreen: View {
    @Environment(\.palette) private var palette
    let coordinator: ProvidersCoordinator
    /// The action that opens the saved wallet.
    let continueSetup: () -> Void

    var body: some View {
        ProvidersScreen(coordinator: coordinator) {
            Section {
                Button("Continue", action: continueSetup)
                    .foregroundStyle(palette.accent)
            }
            .listRowBackground(palette.surface)
        }
        .onChange(of: coordinator.completedKeyChoice) { _, choice in
            if choice != nil { continueSetup() }
        }
    }
}
