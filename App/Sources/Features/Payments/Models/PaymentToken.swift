import Foundation

/// A token the person can pay with, with what they hold and what one token is worth.
nonisolated struct PaymentToken: Identifiable, Hashable, Sendable {
    /// The token's symbol, such as SOL.
    let symbol: String
    /// The quantity the account holds.
    let balance: Decimal
    /// The price of one token in the person's currency, or `nil` when no price is known.
    let price: Decimal?
    /// The number of decimal places the token uses.
    let decimals: Int

    /// Identifies the token by its symbol within the account's list.
    var id: String { symbol }
}
