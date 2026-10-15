import Foundation
import Testing
@testable import widgets

/// Checks which keypad presses the amount accepts and what it shows while the person types.
struct AmountEntryTests {
    /// Types each key in order on a fresh amount.
    /// - Parameters:
    ///   - keys: The keys to press.
    ///   - fractionDigits: How many digits the unit allows after the separator.
    /// - Returns: The amount and whether the last key was accepted.
    private static func type(_ keys: [KeypadKey], fractionDigits: Int = 2) -> (entry: AmountEntry, accepted: Bool) {
        var entry = AmountEntry(maximumFractionDigits: fractionDigits)
        var accepted = true
        for key in keys { accepted = entry.press(key) }
        return (entry, accepted)
    }

    /// Digits and one separator build the amount, keeping trailing zeros as typed.
    @Test func `Digits and a separator build the amount`() {
        let (entry, accepted) = Self.type([.digit(1), .digit(2), .decimalSeparator, .digit(5), .digit(0)])
        #expect(accepted)
        #expect(entry.value == Decimal(string: "12.5"))
        #expect(entry.fractionDigits == "50")
    }

    /// Keys that would break the amount's format leave it unchanged.
    /// - Parameters:
    ///   - keys: The keys before the rejected one, which comes last.
    ///   - fractionDigits: How many digits the unit allows after the separator.
    @Test(arguments: [
        ([KeypadKey.decimalSeparator, .decimalSeparator], 2),
        ([.decimalSeparator], 0),
        ([.digit(0), .digit(0)], 2),
        ([.digit(1), .decimalSeparator, .digit(2), .digit(3), .digit(4)], 2),
        (Array(repeating: KeypadKey.digit(9), count: AmountEntry.maximumIntegerDigits + 1), 2),
    ])
    func `Malformed keys are rejected`(keys: [KeypadKey], fractionDigits: Int) {
        let before = Self.type(Array(keys.dropLast()), fractionDigits: fractionDigits).entry
        let (entry, accepted) = Self.type(keys, fractionDigits: fractionDigits)
        #expect(!accepted)
        #expect(entry == before)
    }

    /// A lone zero gives way to the next digit instead of leading it.
    @Test func `A leading zero is replaced`() {
        let (entry, _) = Self.type([.digit(0), .digit(7)])
        #expect(entry.integerDigits == "7")
    }

    /// Delete removes fraction digits, then the separator, then whole digits, and does nothing when empty.
    @Test func `Delete removes the last typed character`() {
        var entry = Self.type([.digit(4), .decimalSeparator, .digit(2)]).entry
        _ = entry.press(.delete)
        #expect(entry.fractionDigits == "")
        _ = entry.press(.delete)
        #expect(entry.fractionDigits == nil)
        _ = entry.press(.delete)
        #expect(entry == AmountEntry(maximumFractionDigits: 2))
        let accepted = entry.press(.delete)
        #expect(accepted)
        #expect(entry == AmountEntry(maximumFractionDigits: 2))
    }

    /// A converted amount starts as if its digits were typed: rounded down unless asked otherwise, so it never exceeds
    /// what was converted; with every cent when asked, so $12.50 doesn't come back as $12.5; empty when it rounds to
    /// nothing; and refused, instead of cut short, with more whole digits than the keypad types.
    /// - Parameters:
    ///   - value: The converted amount's digits.
    ///   - fractionDigits: How many digits the unit allows after the separator.
    ///   - rounding: How extra digits are dropped.
    ///   - padsFraction: Whether the fraction shows every digit the unit allows.
    ///   - keys: The keys that type the expected amount, or `nil` when the conversion is refused.
    @Test(arguments: [
        ("0.087579198", 4, .down, false,
         [.digit(0), .decimalSeparator, .digit(0), .digit(8), .digit(7), .digit(5)]),
        ("12.5", 2, .plain, true, [.digit(1), .digit(2), .decimalSeparator, .digit(5), .digit(0)]),
        ("12", 2, .plain, true, [.digit(1), .digit(2)]),
        ("0.004", 2, .down, false, []),
        ("1250000000", 2, .down, false, nil),
    ] as [(String, Int, NSDecimalNumber.RoundingMode, Bool, [KeypadKey]?)])
    func `A converted amount starts as if typed`(value: String, fractionDigits: Int,
                                                 rounding: NSDecimalNumber.RoundingMode, padsFraction: Bool,
                                                 keys: [KeypadKey]?) throws {
        let amount = try #require(Decimal(string: value))
        let converted = AmountEntry(amount, maximumFractionDigits: fractionDigits, rounding: rounding,
                                    padsFraction: padsFraction)
        #expect(converted == keys.map { Self.type($0, fractionDigits: fractionDigits).entry })
    }

    /// The amount shows as typed, including a trailing separator, wherever the locale puts the currency.
    /// - Parameters:
    ///   - keys: The keys to press.
    ///   - unit: The amount's unit.
    ///   - locale: The locale's identifier.
    ///   - shown: What the keypad shows.
    @Test(arguments: [
        ([KeypadKey](), AmountEntryFormatStyle.Unit.currency(code: "USD"), "en_US", "$0"),
        ([.digit(1), .digit(2)], .currency(code: "USD"), "en_US", "$12"),
        ([.decimalSeparator], .currency(code: "USD"), "en_US", "$0."),
        ([.digit(1), .digit(2), .digit(3), .digit(4)], .currency(code: "USD"), "en_US", "$1,234"),
        ([.digit(1), .digit(2), .decimalSeparator], .currency(code: "USD"), "en_US", "$12."),
        ([.digit(1), .digit(2), .decimalSeparator, .digit(5), .digit(0)], .currency(code: "USD"), "en_US", "$12.50"),
        ([.digit(1), .digit(2), .decimalSeparator], .currency(code: "EUR"), "de_DE", "12,\u{00A0}€"),
        ([.digit(1), .decimalSeparator, .digit(5)], .token(symbol: "SOL"), "en_US", "1.5 SOL"),
        ([.digit(1), .digit(2), .digit(3), .digit(4), .decimalSeparator, .digit(5)], .token(symbol: "SOL"), "de_DE",
         "1.234,5 SOL"),
        ([.digit(1), .digit(2), .decimalSeparator], .token(symbol: "ai16z"), "en_US", "12. ai16z"),
        ([.digit(1), .digit(2), .decimalSeparator], .token(symbol: "SOL"), "ar@numbers=arab", "\u{0661}\u{0662}\u{066B} SOL"),
    ])
    func `The amount shows as typed`(keys: [KeypadKey], unit: AmountEntryFormatStyle.Unit, locale: String,
                                     shown: String) {
        let entry = Self.type(keys).entry
        #expect(entry.formatted(.entry(in: unit).locale(Locale(identifier: locale))) == shown)
    }
}
