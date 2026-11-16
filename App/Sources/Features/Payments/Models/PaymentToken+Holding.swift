import Foundation
import Portfolio
import Transactions

extension PaymentToken {
    /// Creates a token from a holding, or `nil` when it has no balance or another owner.
    ///
    /// - Parameters:
    ///   - holding: A holding from the account's portfolio.
    ///   - currencyCode: The code of the person's currency, which leaves out prices in other currencies.
    nonisolated init?(holding: Holding, currencyCode: String) {
        guard let balance = holding.balance, balance.amount > 0 else { return nil }
        let price = holding.knownPrice.flatMap { $0.currency == currencyCode ? $0.price : nil }
        self.init(holding: holding, balance: balance, price: price)
    }

    /// Creates a token of a holding's asset with a given balance, or `nil` for another owner's holding.
    ///
    /// - Parameters:
    ///   - holding: A holding from the account's portfolio.
    ///   - balance: The token's balance, such as the holding's own balance or the asset's private balance.
    ///   - price: The price of one token in the person's currency, or `nil` when none is known.
    nonisolated init?(holding: Holding, balance: TokenAmount, price: Decimal?) {
        guard holding.otherOwner == nil else { return nil }
        self.init(asset: holding.asset, balance: balance, price: price)
    }
}
