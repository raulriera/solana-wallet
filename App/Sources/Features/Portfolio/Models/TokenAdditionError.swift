import Foundation
import Portfolio

/// A reason a token couldn't be looked up or added.
nonisolated enum TokenAdditionError: RetryableError, Equatable {
    case rateLimited
    /// The RPC API key is missing or wasn't accepted.
    case keyRejected
    case unsupportedNetwork
    /// The lookup failed for another reason, such as a lost connection.
    case lookupUnavailable
    /// The list holds the most tokens a person can add.
    case limitReached
    /// The saved token list can't be read.
    case listUnreadable
    case saveFailed

    /// Creates an error from a failed lookup.
    ///
    /// - Parameter error: The lookup's error.
    init(lookup error: PortfolioError) {
        self = switch error {
        case .rateLimited: .rateLimited
        case .missingKey, .invalidKey: .keyRejected
        case .unsupportedNetwork: .unsupportedNetwork
        case .unavailable: .lookupUnavailable
        case .listUnreadable: .listUnreadable
        }
    }

    var canRetry: Bool {
        switch self {
        case .rateLimited, .lookupUnavailable, .saveFailed: true
        case .keyRejected, .unsupportedNetwork, .limitReached, .listUnreadable: false
        }
    }

    var errorDescription: String? { String(localized: "Couldn't Add Token") }

    var recoverySuggestion: String? {
        switch self {
        case .rateLimited: String(localized: "Too many requests. Try again in a moment.")
        case .keyRejected: String(localized: "Your RPC API key wasn't accepted.")
        case .unsupportedNetwork:
            String(localized: "Custom RPCs use mainnet. Choose another provider or switch this window to Mainnet in Settings.")
        case .lookupUnavailable: String(localized: "Couldn't check this address. Check your connection and try again.")
        case .limitReached:
            String(localized: "You can add up to \(Portfolio::TokenList.addedTokenLimit) tokens. Remove one to add another.")
        case .listUnreadable: String(localized: "Your token list can't be read, so no token can be added.")
        case .saveFailed: String(localized: "Your token list couldn't be saved. Try again.")
        }
    }
}
