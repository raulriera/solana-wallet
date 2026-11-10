import Foundation

nonisolated extension Decimal {
    /// Returns the value rounded to a number of digits after the separator.
    ///
    /// - Parameters:
    ///   - scale: The number of digits to keep after the separator.
    ///   - mode: The rounding mode for the extra digits.
    /// - Returns: The rounded value.
    func rounded(scale: Int, _ mode: Decimal.RoundingMode) -> Decimal {
        var exact = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &exact, scale, mode)
        return rounded
    }
}
