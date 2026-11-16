import Foundation
import Transactions

nonisolated extension TokenAmount {
    /// Creates the amount of a quantity in whole tokens, or `nil` when the quantity is negative or its units don't
    /// fit in 64 bits.
    ///
    /// - Parameters:
    ///   - quantity: The quantity in whole tokens. Digits below the token's smallest unit are dropped.
    ///   - decimals: The token's decimal places.
    init?(_ quantity: Decimal, decimals: UInt8) {
        let scaled = (quantity * pow(10, Int(decimals))).rounded(scale: 0, .down)
        guard scaled >= 0, scaled <= Decimal(UInt64.max) else { return nil }
        self.init(amount: NSDecimalNumber(decimal: scaled).uint64Value, decimals: decimals)
    }
}
