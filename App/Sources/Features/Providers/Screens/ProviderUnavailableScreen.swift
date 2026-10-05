import SwiftUI

/// Explains that balances need a working Helius key and offers to enter one.
struct ProviderUnavailableScreen: View {
    @Environment(\.palette) private var palette
    @State private var contentInset = LayoutMetrics.contentMargin
    let isKeyRejected: Bool
    let setUp: () -> Void

    var body: some View {
        ScrollView {
            ContentUnavailableView(title, systemImage: "key.slash", description: Text(message))
                .foregroundStyle(palette.primaryText)
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .readableContentMargins(inset: $contentInset)
        .safeAreaBar(edge: .bottom) {
            Button("Enter API Key", action: setUp)
                .buttonStyle(.primary)
                .padding(.horizontal, contentInset)
                .padding(.vertical, LayoutMetrics.actionBarVerticalPadding)
        }
        .background(palette.background)
    }

    /// Names the key's problem.
    private var title: LocalizedStringResource {
        isKeyRejected ? "API Key Not Accepted" : "API Key Required"
    }

    /// Explains why balances aren't shown and what entering a key does.
    private var message: LocalizedStringResource {
        isKeyRejected ? "Helius didn't accept your saved API key. Enter a new key to load your balances."
            : "This wallet needs your Helius API key to load your balances."
    }
}

#Preview("Missing key") {
    ProviderUnavailableScreen(isKeyRejected: false, setUp: {})
}

#Preview("Rejected key") {
    ProviderUnavailableScreen(isKeyRejected: true, setUp: {})
}
