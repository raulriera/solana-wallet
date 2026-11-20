import Foundation
import Transactions

/// The latest landed payment to an address.
nonisolated struct RecentPayment: Identifiable, Hashable, Codable, Sendable {
    let address: Address
    /// When the payment landed.
    let date: Date

    var id: String { address.value }
}
