import Foundation
import Portfolio
import Transactions

extension Holding {
    static func fixture(_ mint: Mint, amount: UInt64?, otherOwner: Address? = nil, imageURL: URL? = nil,
                        valuation: Valuation? = nil) -> Holding {
        Holding(asset: .token(mint), balance: amount.map { TokenAmount(amount: $0, decimals: mint.decimals) },
                otherOwner: otherOwner, imageURL: imageURL, valuation: valuation)
    }
}
