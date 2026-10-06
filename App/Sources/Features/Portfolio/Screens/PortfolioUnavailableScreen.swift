import SwiftUI

/// Explains why the portfolio can't show balances and offers the one action that can fix it.
struct PortfolioUnavailableScreen: View {
    @Environment(\.palette) private var palette
    @State private var contentInset = LayoutMetrics.contentMargin
    let failure: PortfolioFailure
    let action: () -> Void

    var body: some View {
        ScrollView {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
                .foregroundStyle(palette.primaryText)
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .readableContentMargins(inset: $contentInset, addsSafeArea: false)
        .safeAreaBar(edge: .bottom) {
            Button(actionTitle, action: action)
                .buttonStyle(.primary)
                .padding(.horizontal, contentInset)
                .padding(.vertical, LayoutMetrics.actionBarVerticalPadding)
        }
        .background(palette.background)
    }

    /// Names what went wrong.
    private var title: LocalizedStringResource {
        switch failure {
        case .missingKey: "API Key Required"
        case .invalidKey: "API Key Not Accepted"
        case .rateLimited: "Too Many Requests"
        case .unavailable: "Balances Unavailable"
        }
    }

    /// Explains why balances aren't shown and what the action does.
    private var message: LocalizedStringResource {
        switch failure {
        case .missingKey: "This wallet needs your Helius API key to load your balances."
        case .invalidKey: "Helius didn't accept your saved API key. Enter a new key to load your balances."
        case .rateLimited: "Your provider is limiting requests. Wait a moment, then try again."
        case .unavailable: "Your balances couldn't be loaded. Check your connection, then try again."
        }
    }

    /// Pictures the cause: the key, the provider's limit, or the connection.
    private var systemImage: String {
        switch failure {
        case .missingKey, .invalidKey: "key.slash"
        case .rateLimited: "hourglass"
        case .unavailable: "wifi.exclamationmark"
        }
    }

    /// A new key fixes key failures; other failures need another try.
    private var actionTitle: LocalizedStringResource {
        failure.requiresProviderSetup ? "Enter API Key" : "Try Again"
    }
}

#Preview("Missing key") {
    PortfolioUnavailableScreen(failure: .missingKey, action: {})
}

#Preview("Rate limited") {
    PortfolioUnavailableScreen(failure: .rateLimited, action: {})
}
