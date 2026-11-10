import Foundation

/// The amount typed on the keypad, with its trailing separator and zeros as typed.
nonisolated struct AmountEntry: Equatable, Sendable {
    static let maximumIntegerDigits = 9

    /// The whole digits without leading zeros, or `"0"` when the person typed a lone zero.
    private(set) var integerDigits = ""
    /// The digits after the separator, or `nil` until the person types the separator.
    private(set) var fractionDigits: String?
    let maximumFractionDigits: Int

    /// Creates an empty amount.
    ///
    /// - Parameter maximumFractionDigits: How many digits the unit allows after the separator.
    init(maximumFractionDigits: Int) {
        self.maximumFractionDigits = maximumFractionDigits
    }

    /// Creates an amount rounded to the unit's digits, or `nil` when it has more whole digits than the keypad types.
    ///
    /// - Parameters:
    ///   - value: The amount to show.
    ///   - maximumFractionDigits: How many digits the unit allows after the separator.
    ///   - rounding: The rounding mode for extra digits.
    ///   - padsFraction: Whether a fraction shows every digit the unit allows.
    init?(_ value: Decimal, maximumFractionDigits: Int, rounding: Decimal.RoundingMode = .down,
          padsFraction: Bool = false) {
        self.init(maximumFractionDigits: maximumFractionDigits)
        let rounded = value.rounded(scale: maximumFractionDigits, rounding)
        guard rounded > 0 else { return }
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
    /// - Parameter key: The pressed key.
    /// - Returns: `false` when the key was rejected.
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
