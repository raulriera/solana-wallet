import Foundation

/// What a transaction result's card shows.
struct TransactionResultCard {
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let systemImage: String

    /// Returns the card of a transaction that waits to settle.
    ///
    /// - Parameter error: Why the transaction's check stopped, or `nil` while it runs.
    /// - Returns: The card.
    static func pending(_ error: ConfirmationError?) -> TransactionResultCard {
        switch error {
        case nil:
            TransactionResultCard(
                title: "Sending",
                message: "Waiting for the network to confirm it.",
                systemImage: "clock.circle.fill")
        case .rateLimited?:
            TransactionResultCard(
                title: "Too Many Requests",
                message: "Your provider is limiting requests. The explorer shows whether it went through.",
                systemImage: "hourglass.circle.fill")
        case .invalidKey?:
            TransactionResultCard(
                title: "API Key Not Accepted",
                message: "Your provider didn't accept your saved API key. Enter a new key in Settings.",
                systemImage: "key.circle.fill")
        case .unavailable?:
            TransactionResultCard(
                title: "Status Unavailable",
                message: "Your provider can't check it. Choose another provider in Settings.",
                systemImage: "wifi.exclamationmark.circle.fill")
        }
    }

    /// Returns the card of a transaction that the network rejected.
    ///
    /// - Parameters:
    ///   - title: The card's title.
    ///   - message: What the failure cost.
    /// - Returns: The card.
    static func failed(title: LocalizedStringResource, message: LocalizedStringResource) -> TransactionResultCard {
        TransactionResultCard(title: title, message: message, systemImage: "exclamationmark.triangle.fill")
    }

    /// Returns the card of a transaction that was never sent.
    ///
    /// - Parameter message: What stayed in the wallet.
    /// - Returns: The card.
    static func dropped(message: LocalizedStringResource) -> TransactionResultCard {
        TransactionResultCard(title: "Not Sent", message: message, systemImage: "xmark.circle.fill")
    }
}
