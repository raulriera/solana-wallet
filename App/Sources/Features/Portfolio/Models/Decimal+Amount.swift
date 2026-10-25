import Foundation
import Portfolio

nonisolated extension Decimal {
    /// An exact token quantity in whole tokens, without floating-point conversion.
    /// - Parameter amount: The quantity in the token's smallest units.
    init(_ amount: Amount) {
        self.init(sign: .plus, exponent: -Int(amount.decimals), significand: Decimal(amount.units))
    }
}
