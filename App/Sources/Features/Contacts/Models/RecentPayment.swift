import Foundation
import Transactions

/// The latest landed payment to an address.
nonisolated struct RecentPayment: Identifiable, Hashable, Codable, Sendable {
    let address: Address
    /// When the payment landed.
    let date: Date

    var id: String { address.value }

    /// The payment's persisted field names.
    private enum CodingKeys: String, CodingKey {
        case address, date
    }
}

nonisolated extension RecentPayment {
    /// Creates the recent payment of a sent payment's record, or `nil` when the record has no recipient.
    ///
    /// - Parameter record: The payment's record.
    init?(_ record: TransactionRecord) {
        guard let recipient = record.kind.recipient else { return nil }
        self.init(address: recipient, date: record.settled ?? record.created)
    }
}
