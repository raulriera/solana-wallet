import Foundation

/// An error that stops a payment.
nonisolated enum SendError: TransactionReviewError, CaseIterable {
    /// The account's SOL doesn't cover the payment and its network fee.
    case notEnoughSOL
    /// The payment would open the recipient's address with less SOL than it needs to exist.
    case amountTooSmall
    case preparationFailed
    case notSent

    var errorDescription: String? {
        switch self {
        case .notEnoughSOL: String(localized: "Not Enough SOL")
        case .amountTooSmall: String(localized: "Amount Too Small")
        case .preparationFailed: String(localized: "Couldn't Prepare Payment")
        case .notSent: String(localized: "Couldn't Send Payment")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notEnoughSOL:
            String(localized: "This payment and its network fee need more SOL than this account has.")
        case .amountTooSmall:
            String(localized: "This address has no SOL yet. Send a larger amount to open it.")
        case .preparationFailed:
            String(localized: "Try again in a moment.")
        case .notSent:
            String(localized: "Nothing left your wallet. Try again in a moment.")
        }
    }

    var canRetry: Bool {
        switch self {
        case .notEnoughSOL, .amountTooSmall: false
        case .preparationFailed, .notSent: true
        }
    }
}
