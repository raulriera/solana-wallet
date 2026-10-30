import Foundation
import Testing
@testable import widgets

struct AmountEntryTests {
    private static func type(_ keys: [KeypadKey], fractionDigits: Int = 2) -> (entry: AmountEntry, accepted: Bool) {
        var entry = AmountEntry(maximumFractionDigits: fractionDigits)
        var accepted = true
        for key in keys { accepted = entry.press(key) }
        return (entry, accepted)
    }

    @Test func `Digits and a separator build the amount`() {
        let (entry, accepted) = Self.type([.digit(1), .digit(2), .decimalSeparator, .digit(5), .digit(0)])
        #expect(accepted)
        #expect(entry.value == Decimal(string: "12.5"))
        #expect(entry.fractionDigits == "50")
    }

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

    @Test func `A leading zero is replaced`() {
        let (entry, _) = Self.type([.digit(0), .digit(7)])
        #expect(entry.integerDigits == "7")
    }

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

    @Test(arguments: [
        ([KeypadKey](), AmountEntryFormatStyle.Unit.currency(code: "USD"), "en_US", "$0"),
        ([.digit(1), .digit(2)], .currency(code: "USD"), "en_US", "$12"),
        ([.decimalSeparator], .currency(code: "USD"), "en_US", "$0."),
        ([.digit(1), .digit(2), .digit(3), .digit(4)], .currency(code: "USD"), "en_US", "$1,234"),
        ([.digit(1), .digit(2), .decimalSeparator], .currency(code: "USD"), "en_US", "$12."),
        ([.digit(1), .digit(2), .decimalSeparator, .digit(5), .digit(0)], .currency(code: "USD"), "en_US", "$12.50"),
        ([.digit(1), .digit(2), .decimalSeparator], .currency(code: "EUR"), "de_DE", "12,\u{00A0}€"),
        ([.digit(1), .digit(2), .decimalSeparator, .digit(5), .digit(0)], .currency(code: "EUR"), "de_DE",
         "12,50\u{00A0}€"),
        ([.digit(1), .digit(2), .decimalSeparator, .digit(5), .digit(0)], .currency(code: "USD"), "de_DE",
         "12,50\u{00A0}$"),
        ([.digit(1), .digit(2), .digit(3), .digit(4), .decimalSeparator, .digit(5)], .currency(code: "EUR"), "fr_FR",
         "1\u{202F}234,5\u{00A0}€"),
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
