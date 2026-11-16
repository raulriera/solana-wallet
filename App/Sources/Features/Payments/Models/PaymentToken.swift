import Foundation
import Transactions

/// A token the person can pay with, with its balance and price.
nonisolated struct PaymentToken: Identifiable, Hashable, Sendable {
    let asset: Asset
    let balance: TokenAmount
    /// The price of one token in the person's currency, or `nil` when no price is known.
    let price: Decimal?

    var id: Asset.ID { asset.id }
}
