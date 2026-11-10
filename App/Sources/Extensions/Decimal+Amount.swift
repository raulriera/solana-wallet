import Foundation
import Portfolio

nonisolated extension Decimal {
    /// Creates an exact quantity in whole tokens.
    ///
    /// - Parameter amount: The quantity in the token's smallest units.
    init(_ amount: Amount) {
        self.init(sign: .plus, exponent: -Int(amount.decimals), significand: Decimal(amount.units))
    }
}
