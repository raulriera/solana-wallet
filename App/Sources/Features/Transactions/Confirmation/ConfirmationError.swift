import Foundation
import RPC

/// Why the check of a sent transaction stopped before the transaction settled.
nonisolated enum ConfirmationError: LocalizedError {
    case rateLimited
    /// The provider refused the API key.
    case invalidKey
    /// The provider can't check the transaction.
    case unavailable

    /// Creates the reason from the error that stopped the check.
    ///
    /// - Parameter error: The error that stopped the check.
    init(_ error: any Error) {
        switch error {
        case let error as RPCError where error.isRateLimited: self = .rateLimited
        case RPCProviderError.invalidKey: self = .invalidKey
        default: self = .unavailable
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .rateLimited: "Too Many Requests"
        case .invalidKey: "API Key Not Accepted"
        case .unavailable: "Status Unavailable"
        }
    }

    /// What the stop means and what fixes it.
    var message: LocalizedStringResource {
        switch self {
        case .rateLimited: "Your provider is limiting requests. The explorer shows whether it went through."
        case .invalidKey: "Your provider didn't accept your saved API key. Enter a new key in Settings."
        case .unavailable: "Your provider can't check it. Choose another provider in Settings."
        }
    }

    var errorDescription: String? { String(localized: title) }

    var recoverySuggestion: String? { String(localized: message) }
}
