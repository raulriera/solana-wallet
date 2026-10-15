import Foundation
import Portfolio

/// Why the add-token sheet couldn't look up or add a token, explained in an alert without the provider's error.
nonisolated enum TokenAdditionError: RetryableError, Equatable {
    /// A provider is limiting the lookup's requests.
    case rateLimited
    /// The RPC API key is missing or wasn't accepted.
    case keyRejected
    /// The selected custom RPC doesn't serve the portfolio's network.
    case unsupportedNetwork
    /// The lookup couldn't finish for another reason, such as a lost connection.
    case lookupUnavailable
    /// The list already holds the most tokens a person can add.
    case limitReached
    /// The saved token list can't be read, so no token can be added.
    case listUnreadable
    /// The token list couldn't be saved.
    case saveFailed

    /// Classifies a failed lookup by what the person can do about it.
    /// - Parameter error: The lookup's error, classified as the portfolio classifies it.
    init(lookup error: PortfolioError) {
        self = switch error {
        case .rateLimited: .rateLimited
        case .missingKey, .invalidKey: .keyRejected
        case .unsupportedNetwork: .unsupportedNetwork
        case .unavailable: .lookupUnavailable
        case .listUnreadable: .listUnreadable
        }
    }

    /// Whether trying again can help; a new key, another provider, a removed token, or a readable list can't come
    /// from a retry.
    var canRetry: Bool {
        switch self {
        case .rateLimited, .lookupUnavailable, .saveFailed: true
        case .keyRejected, .unsupportedNetwork, .limitReached, .listUnreadable: false
        }
    }

    /// The alert's title.
    var errorDescription: String? { String(localized: "Couldn't Add Token") }

    /// What went wrong and what to do about it, without naming the provider.
    var recoverySuggestion: String? {
        switch self {
        case .rateLimited: String(localized: "Too many requests. Try again in a moment.")
        case .keyRejected: String(localized: "Your RPC API key wasn't accepted.")
        case .unsupportedNetwork:
            String(localized: "Custom RPCs use mainnet. Choose another provider or switch this window to Mainnet in Settings.")
        case .lookupUnavailable: String(localized: "Couldn't check this address. Check your connection and try again.")
        case .limitReached:
            // The app's own TokenList view hides the framework's type, so the module selector names it.
            String(localized: "You can add up to \(Portfolio::TokenList.addedTokenLimit) tokens. Remove one to add another.")
        case .listUnreadable: String(localized: "Your token list can't be read, so no token can be added.")
        case .saveFailed: String(localized: "Your token list couldn't be saved. Try again.")
        }
    }
}
