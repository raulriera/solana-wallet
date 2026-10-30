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
        guard holding.otherOwner == nil, let amount = holding.amount, amount.units > 0 else { return nil }
        let mint: Address?
        switch holding.id {
        case .nativeSOL: mint = nil
        case .asset(let value):
            guard let address = try? Address(value) else { return nil }
            mint = address
        }
        let price = holding.knownPrice.flatMap { $0.currency == currencyCode ? $0.price : nil }
        self.init(mint: mint, symbol: holding.displaySymbol,
                  balance: Decimal(amount),
                  price: price, decimals: Int(amount.decimals))
    }
}
