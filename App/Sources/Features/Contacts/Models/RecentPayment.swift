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
