import SwiftUI

/// Explains why the portfolio can't show balances and offers the one action that can fix it, if any.
struct PortfolioUnavailableScreen: View {
    let error: PortfolioError
    let action: () -> Void

    var body: some View {
        UnavailableScreen(title: title, message: message, systemImage: systemImage) {
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.primary)
            }
        }
    }

    /// Names what went wrong.
    private var title: LocalizedStringResource {
        switch error {
        case .missingKey: "API Key Required"
        case .invalidKey: "API Key Not Accepted"
        case .unsupportedNetwork: "Custom RPCs Use Mainnet"
        case .rateLimited: "Too Many Requests"
        case .unavailable: "Balances Unavailable"
        case .listUnreadable: "Token List Unavailable"
        }
    }

    /// Explains why balances aren't shown and what the action does.
    private var message: LocalizedStringResource {
        switch error {
        case .missingKey: "This wallet needs your Helius API key to load your balances."
        case .invalidKey: "Helius didn't accept your saved API key. Enter a new key to load your balances."
        case .unsupportedNetwork: "Choose another provider or switch this window to Mainnet in Settings."
        case .rateLimited: "Your provider is limiting requests. Wait a moment, then try again."
        case .unavailable: "Your balances couldn't be loaded. Check your connection, then try again."
        case .listUnreadable: "Your token list can't be read, so your balances can't load."
        }
    }

    /// Pictures the cause: the key, the provider's network, the provider's limit, the connection, or the saved list.
    private var systemImage: String {
        switch error {
        case .missingKey, .invalidKey: "key.slash"
        case .unsupportedNetwork: "network.slash"
        case .rateLimited: "hourglass"
        case .unavailable: "wifi.exclamationmark"
        case .listUnreadable: "exclamationmark.triangle.text.page"
        }
    }

    /// A new key fixes key failures and another try fixes passing ones; another provider or Mainnet, chosen in
    /// Settings, fixes an unsupported network, and nothing in the app fixes an unreadable list.
    private var actionTitle: LocalizedStringResource? {
        switch error {
        case .missingKey, .invalidKey: "Enter API Key"
        case .rateLimited, .unavailable: "Try Again"
        case .unsupportedNetwork, .listUnreadable: nil
        }
    }
}

#Preview("Missing key") {
    PortfolioUnavailableScreen(error: .missingKey, action: {})
}

#Preview("Unsupported network") {
    PortfolioUnavailableScreen(error: .unsupportedNetwork, action: {})
}

#Preview("Rate limited") {
    PortfolioUnavailableScreen(error: .rateLimited, action: {})
}

#Preview("Unreadable list") {
    PortfolioUnavailableScreen(error: .listUnreadable, action: {})
}
