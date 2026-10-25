import Foundation

/// A payment error that the app explains in an alert, without underlying errors.
nonisolated enum SendError: RetryableError, Equatable, CaseIterable {
    /// The account's SOL doesn't cover the payment and its network fee, as the simulation found.
    case notEnoughSOL
    /// The payment couldn't be prepared or simulated for another reason, such as a provider error.
    case preparationFailed
    /// The payment couldn't be signed or sent, so nothing left the wallet.
    case notSent
    /// The payment was sent, but the provider stopped answering before it settled, such as after a rate limit.
    case watchStopped

    /// The alert's title.
    var errorDescription: String? {
        switch self {
        case .notEnoughSOL: String(localized: "Not Enough SOL")
        case .preparationFailed: String(localized: "Couldn't Prepare Payment")
        case .notSent: String(localized: "Couldn't Send Payment")
        case .watchStopped: String(localized: "Couldn't Check Payment")
        }
    }

    /// The alert's message.
    var recoverySuggestion: String? {
        switch self {
        case .notEnoughSOL:
            String(localized: "This payment and its network fee need more SOL than this account has.")
        case .preparationFailed:
            String(localized: "Try again in a moment.")
        case .notSent:
            String(localized: "Nothing left your wallet. Try again in a moment.")
        case .watchStopped:
            String(localized: "Your payment was sent, but the RPC provider stopped answering.")
        }
    }

    /// Whether repeating the step that failed can help: a simulation that ran out of SOL fails the same way again.
    var canRetry: Bool { self != .notEnoughSOL }
}
