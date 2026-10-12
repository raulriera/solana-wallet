import SwiftUI

/// Shows Providers, as Settings does, with a pinned action that opens the new wallet with the provider in use.
struct ProviderChoiceScreen: View {
    @State private var contentInset = LayoutMetrics.contentMargin
    let flow: ProvidersFlow
    /// Opens the saved wallet.
    let continueSetup: () -> Void

    var body: some View {
        ProvidersScreen(flow: flow)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .readableContentMargins(inset: $contentInset)
            .safeAreaBar(edge: .bottom) {
                Button("Continue", action: continueSetup)
                    .buttonStyle(.primary)
                    .padding(.horizontal, contentInset)
                    .padding(.vertical, LayoutMetrics.actionBarVerticalPadding)
            }
    }
}
