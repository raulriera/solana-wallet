import Foundation

/// What a transaction result's card shows.
struct TransactionResultCard {
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let systemImage: String

    /// The card of a transaction that waits to settle.
    static let sending = TransactionResultCard(title: "Sending", message: "Waiting for the network to confirm it.",
                                               systemImage: "clock.circle.fill")

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
