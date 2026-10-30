import Foundation

/// An error that stops a payment.
nonisolated enum SendError: TransactionReviewError, CaseIterable {
    /// The account's SOL doesn't cover the payment and its network fee.
    case notEnoughSOL
    case preparationFailed
    case notSent

    var errorDescription: String? {
        switch self {
        case .notEnoughSOL: String(localized: "Not Enough SOL")
        case .preparationFailed: String(localized: "Couldn't Prepare Payment")
        case .notSent: String(localized: "Couldn't Send Payment")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notEnoughSOL:
            String(localized: "This payment and its network fee need more SOL than this account has.")
        case .preparationFailed:
            String(localized: "Try again in a moment.")
        case .notSent:
            String(localized: "Nothing left your wallet. Try again in a moment.")
        }
    }

    var canRetry: Bool { self != .notEnoughSOL }
}
