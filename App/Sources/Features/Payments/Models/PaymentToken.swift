import Foundation
import Transactions

/// A token the person can pay with, with its balance and price.
nonisolated struct PaymentToken: Identifiable, Hashable, Sendable {
    /// The token's mint address, or `nil` for native SOL.
    let mint: Address?
    let symbol: String
    let balance: Decimal
    /// The price of one token in the person's currency, or `nil` when no price is known.
    let price: Decimal?
    let decimals: Int

    var id: Address? { mint }
}
