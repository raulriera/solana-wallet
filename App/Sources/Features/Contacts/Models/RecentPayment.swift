import Foundation
import Transactions

/// The latest landed payment to an address.
nonisolated struct RecentPayment: Identifiable, Hashable, Sendable {
    /// The address the payment went to.
    let address: Address
    /// When the payment landed.
    let date: Date

    /// Identifies the payment by its address, since each address keeps only its latest payment.
    var id: String { address.value }
}

nonisolated extension RecentPayment {
    /// Creates the recent payment of a sent payment's record.
    /// - Parameter record: The payment's record.
    /// - Returns: `nil` for a move between the account's own balances, which has no recipient.
    init?(_ record: TransactionRecord) {
        guard let recipient = record.kind.recipient else { return nil }
        self.init(address: recipient, date: record.settled ?? record.created)
    }
}
