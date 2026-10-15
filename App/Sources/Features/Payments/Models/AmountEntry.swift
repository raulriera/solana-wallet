import Foundation

/// The amount typed on the keypad, kept as typed so a trailing separator and trailing zeros stay on screen.
nonisolated struct AmountEntry: Equatable, Sendable {
    /// The largest number of whole digits an amount can have.
    static let maximumIntegerDigits = 9

    /// The whole digits without leading zeros, or `"0"` when the person typed a lone zero.
    private(set) var integerDigits = ""
    /// The digits after the separator, or `nil` until the person types the separator.
    private(set) var fractionDigits: String?
    /// How many digits the unit allows after the separator, such as 2 for dollars or 9 for SOL.
    let maximumFractionDigits: Int

    /// Starts an empty amount.
    /// - Parameter maximumFractionDigits: How many digits the unit allows after the separator.
    init(maximumFractionDigits: Int) {
        self.maximumFractionDigits = maximumFractionDigits
    }

    /// Starts from an existing amount, such as one converted from another unit, rounded to the unit's digits.
    /// - Parameters:
    ///   - value: The amount to show.
    ///   - maximumFractionDigits: How many digits the unit allows after the separator.
    ///   - rounding: How to drop extra digits; rounding down never shows more than was converted.
    ///   - padsFraction: Whether a fraction shows every digit the unit allows, as a currency shows cents.
    /// - Returns: The amount, empty when it rounds to zero, or `nil` when it has more whole digits than the keypad
    ///   can type.
    init?(_ value: Decimal, maximumFractionDigits: Int, rounding: NSDecimalNumber.RoundingMode = .down,
          padsFraction: Bool = false) {
        self.init(maximumFractionDigits: maximumFractionDigits)
        var source = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, maximumFractionDigits, rounding)
        guard rounded > 0 else { return }
        // The decimal number's own text keeps every digit, without grouping or a locale's separator.
        let parts = NSDecimalNumber(decimal: rounded).stringValue.split(separator: ".", omittingEmptySubsequences: false)
        guard parts[0].count <= Self.maximumIntegerDigits else { return nil }
        integerDigits = String(parts[0])
        if parts.count > 1 {
            let fraction = String(parts[1])
            fractionDigits = padsFraction
                ? fraction.padding(toLength: maximumFractionDigits, withPad: "0", startingAt: 0)
                : fraction
        }
    }

    /// The typed amount, or zero when nothing has been typed.
    var value: Decimal {
        let whole = integerDigits.isEmpty ? "0" : integerDigits
        return Decimal(string: "\(whole).\(fractionDigits ?? "")", locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    /// Applies a key press when it keeps the amount well formed.
    ///
    /// The keypad rejects a second separator, a separator in a unit without fractions, a leading zero
    /// before another zero, and digits beyond the unit's limits. Delete on an empty amount does nothing.
    /// - Parameter key: The pressed key.
    /// - Returns: `false` when the key was rejected, so the screen can signal it.
    mutating func press(_ key: KeypadKey) -> Bool {
        switch key {
        case .digit(let digit):
            if let fraction = fractionDigits {
                guard fraction.count < maximumFractionDigits else { return false }
                fractionDigits = fraction + String(digit)
            } else if integerDigits == "0" {
                guard digit != 0 else { return false }
                integerDigits = String(digit)
            } else {
                guard integerDigits.count < Self.maximumIntegerDigits else { return false }
                integerDigits += String(digit)
            }
        case .decimalSeparator:
            guard fractionDigits == nil, maximumFractionDigits > 0 else { return false }
            fractionDigits = ""
        case .delete:
            if let fraction = fractionDigits {
                fractionDigits = fraction.isEmpty ? nil : String(fraction.dropLast())
            } else if !integerDigits.isEmpty {
                integerDigits.removeLast()
            }
        }
        return true
    }
}
