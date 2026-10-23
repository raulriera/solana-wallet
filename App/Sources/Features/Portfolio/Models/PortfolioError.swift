import Foundation
import Portfolio
import RPC

/// Why the portfolio couldn't load or refresh, classified by what the person can do about it.
nonisolated enum PortfolioError: Error, Equatable {
    /// The selected provider needs an API key, and none is saved on this device.
    case missingKey
    /// The selected provider rejected the saved key.
    case invalidKey
    /// The selected custom RPC doesn't serve the portfolio's network.
    case unsupportedNetwork
    /// A provider is limiting requests; the person decides when to try again.
    case rateLimited
    /// The portfolio couldn't load or refresh for another reason, such as a lost connection.
    case unavailable
    /// The saved token list can't be read, so trying again can't load the balances.
    case listUnreadable

    /// Classifies an error reported by a portfolio update.
    /// - Parameter error: The failed update's error, which isn't retained.
    init(_ error: any Error) {
        switch error {
        case ProviderClientError.missingKey: self = .missingKey
        case ProviderClientError.invalidKey: self = .invalidKey
        case ProviderClientError.unsupportedNetwork: self = .unsupportedNetwork
        case let error as RPCError where error.isRateLimited: self = .rateLimited
        case TokenListError.unreadable: self = .listUnreadable
        default: self = .unavailable
        }
    }

    /// Whether the portfolio can load only after the person enters a new key or chooses another provider.
    var requiresProviderSetup: Bool { self == .missingKey || self == .invalidKey || self == .unsupportedNetwork }

    /// Why the shown balances may be out of date, or `nil` when the failure hides the balances instead.
    var staleStatus: LocalizedStringResource? {
        switch self {
        case .rateLimited: "Too many requests"
        case .unavailable, .listUnreadable: "Couldn't update balances"
        case .missingKey, .invalidKey, .unsupportedNetwork: nil
        }
    }
}
