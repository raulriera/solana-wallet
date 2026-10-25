import Foundation
import Portfolio
import Transactions

extension PaymentToken {
    /// A holding that the account can pay with: one with a balance that the account itself controls.
    /// - Parameters:
    ///   - holding: A holding from the account's portfolio.
    ///   - currencyCode: The ISO code of the person's currency; a price in another currency is left out.
    /// - Returns: The token, or `nil` when the balance is unknown or zero, another address controls it, or the mint
    ///   isn't a valid address.
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
                  balance: Decimal(sign: .plus, exponent: -Int(amount.decimals), significand: Decimal(amount.units)),
                  price: price, decimals: Int(amount.decimals))
    }
}
