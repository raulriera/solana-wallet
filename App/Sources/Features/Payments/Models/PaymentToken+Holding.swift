import Foundation
import Portfolio
import Transactions

extension PaymentToken {
    /// Creates a token from a holding, or `nil` when it has no balance, another owner, or an invalid mint.
    ///
    /// - Parameters:
    ///   - holding: A holding from the account's portfolio.
    ///   - currencyCode: The code of the person's currency, which leaves out prices in other currencies.
    nonisolated init?(holding: Holding, currencyCode: String) {
        guard let amount = holding.amount, amount.units > 0 else { return nil }
        let price = holding.knownPrice.flatMap { $0.currency == currencyCode ? $0.price : nil }
        self.init(holding: holding, balance: amount, price: price)
    }

    /// Creates a token of a holding's asset with a given balance, or `nil` for another owner's holding or an invalid
    /// mint.
    ///
    /// - Parameters:
    ///   - holding: A holding from the account's portfolio.
    ///   - balance: The token's balance, such as the holding's own amount or the asset's private balance.
    ///   - price: The price of one token in the person's currency, or `nil` when none is known.
    nonisolated init?(holding: Holding, balance: Amount, price: Decimal?) {
        guard holding.otherOwner == nil else { return nil }
        let mint: Address?
        switch holding.id {
        case .nativeSOL: mint = nil
        case .asset(let value):
            guard let address = try? Address(value) else { return nil }
            mint = address
        }
        self.init(
            mint: mint,
            symbol: holding.displaySymbol,
            balance: Decimal(balance),
            price: price,
            decimals: Int(balance.decimals)
        )
    }
}
