import Foundation
import Transactions

/// Who a payment goes to: an address, with the name it's saved under when it's saved.
nonisolated struct PaymentRecipient: Hashable, Sendable {
    /// The address the payment goes to.
    let address: Address
    /// The name the address is saved under, or `nil` when it isn't saved.
    let name: String?

    /// The name, or the shortened address when the address isn't saved.
    var title: String { name ?? address.formatted(.shortAddress) }

    /// The shortened address under a name, or empty when the title already shows it.
    var subtitle: String { name == nil ? "" : address.formatted(.shortAddress) }
}
