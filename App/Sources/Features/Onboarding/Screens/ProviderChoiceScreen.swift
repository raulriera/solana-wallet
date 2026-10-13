import SwiftUI

/// Shows Providers, as Settings does, with a pinned action that opens the new wallet with the provider in use.
struct ProviderChoiceScreen: View {
    @State private var contentInset = LayoutMetrics.contentMargin
    let coordinator: ProvidersCoordinator
    /// Opens the saved wallet.
    let continueSetup: () -> Void

    var body: some View {
        ProvidersScreen(coordinator: coordinator)
            .readableContentMargins(inset: $contentInset)
            .pinnedAction(inset: contentInset) {
                Button("Continue", action: continueSetup)
                    .buttonStyle(.primary)
            }
    }
}
