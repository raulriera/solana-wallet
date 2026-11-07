import Foundation
import Portfolio
import RPC

/// A reason the portfolio couldn't load or refresh.
nonisolated enum PortfolioError: Error, Equatable {
    case missingKey
    case invalidKey
    case unsupportedNetwork
    case rateLimited
    /// Any other failure, such as a lost connection.
    case unavailable
    /// The saved token list can't be read.
    case listUnreadable

    /// Creates an error from a failed portfolio update.
    ///
    /// - Parameter error: The failed update's error.
    init(_ error: any Error) {
        switch error {
        case RPCProviderError.missingKey: self = .missingKey
        case RPCProviderError.invalidKey: self = .invalidKey
        case RPCProviderError.unsupportedNetwork: self = .unsupportedNetwork
        case let error as RPCError where error.isRateLimited: self = .rateLimited
        case TokenListError.unreadable: self = .listUnreadable
        default: self = .unavailable
        }
    }

    /// Whether the person must enter a new key or choose another provider.
    var requiresProviderSetup: Bool { self == .missingKey || self == .invalidKey || self == .unsupportedNetwork }

    /// Why the shown balances or prices may be out of date, or `nil` when the error hides them.
    var staleStatus: LocalizedStringResource? {
        switch self {
        case .rateLimited: "Too many requests"
        case .unavailable, .listUnreadable: "Couldn't update"
        case .missingKey, .invalidKey, .unsupportedNetwork: nil
        }
    }
}
