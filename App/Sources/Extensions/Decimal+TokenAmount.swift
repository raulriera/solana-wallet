import Foundation
import Transactions

nonisolated extension Decimal {
    /// Creates an exact quantity in whole tokens.
    ///
    /// - Parameter tokenAmount: The quantity in the token's smallest units.
    init(_ tokenAmount: TokenAmount) {
        self.init(sign: .plus, exponent: -Int(tokenAmount.decimals), significand: Decimal(tokenAmount.amount))
    }
}
