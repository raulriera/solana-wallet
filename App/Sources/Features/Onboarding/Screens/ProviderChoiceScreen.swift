import SwiftUI

/// Shows Providers, as Settings does, with a last section that opens the new wallet with the provider in use.
///
/// A key entered to choose a provider opens the wallet once that provider is chosen, without another tap.
struct ProviderChoiceScreen: View {
    @Environment(\.palette) private var palette
    let coordinator: ProvidersCoordinator
    /// Opens the saved wallet.
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
