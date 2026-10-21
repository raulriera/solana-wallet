import Foundation
import Testing
@testable import widgets

/// Checks how a payment converts the typed amount, guards the balance, and changes tokens and units.
@MainActor
struct PaymentModelTests {
    /// SOL at $143.87 with 1.23 held, so the whole balance is worth $176.9601.
    nonisolated private static let sol = PaymentToken(symbol: "SOL", balance: Decimal(string: "1.23")!,
                                          price: Decimal(string: "143.87"), decimals: 9)
    /// A dollar stablecoin.
    nonisolated private static let usdc = PaymentToken(symbol: "USDC", balance: 40, price: 1, decimals: 6)
    /// A token without a known price.
    nonisolated private static let unpriced = PaymentToken(symbol: "NOPRICE", balance: 1_000, price: nil, decimals: 5)
    /// A token worth a tiny fraction of a cent.
    nonisolated private static let tiny = PaymentToken(symbol: "TINY", balance: 10_000_000_000, price: Decimal(string: "0.00002"),
                                           decimals: 5)

    /// An empty payment typed in a currency, starting in a token.
    /// - Parameters:
    ///   - token: The token the payment starts in.
    ///   - currencyCode: The ISO code of the person's currency.
    /// - Returns: The payment.
    private static func payment(in token: PaymentToken = sol, currencyCode: String = "USD") -> PaymentModel {
        PaymentModel(tokens: [token] + [sol, usdc, unpriced, tiny].filter { $0 != token }, currencyCode: currencyCode)
    }

    /// Types each key in order.
    /// - Parameters:
    ///   - keys: The keys to press.
    ///   - payment: The payment that receives them.
    private static func type(_ keys: [KeypadKey], into payment: PaymentModel) {
        keys.forEach(payment.press)
    }

    /// Dollars convert to tokens at the token's price, rounded down to the token's decimals.
    @Test func `A currency amount converts to tokens`() {
        let payment = Self.payment()
        Self.type([.digit(1), .digit(2)], into: payment)
        #expect(payment.value == 12)
        #expect(payment.quantity == Decimal(string: "0.083408632"))
        #expect(payment.canSend)
    }

    /// Nothing can't be sent.
    @Test func `An empty amount can't be sent`() {
        #expect(!Self.payment().canSend)
    }

    /// A currency amount worth less than the token's smallest unit comes to no tokens, so it can't be sent.
    @Test func `An amount below the token's smallest unit can't be sent`() {
        let coarse = PaymentToken(symbol: "COARSE", balance: 10, price: 100_000, decimals: 2)
        let payment = Self.payment(in: coarse)
        Self.type([.decimalSeparator, .digit(5), .digit(0)], into: payment)
        #expect(payment.value == Decimal(string: "0.5"))
        #expect(payment.quantity == 0)
        #expect(!payment.canSend)
    }

    /// The whole balance can be sent, and the smallest step past it can't, in tokens or in dollars.
    /// - Parameters:
    ///   - token: The token the payment moves.
    ///   - within: The keys for the largest amount within the balance.
    ///   - past: The keys for the smallest amount past it.
    @Test(arguments: [
        (unpriced, [KeypadKey.digit(1), .digit(0), .digit(0), .digit(0)],
         [KeypadKey.digit(1), .digit(0), .digit(0), .digit(0), .decimalSeparator, .digit(0), .digit(0), .digit(0),
          .digit(0), .digit(1)]),
        (sol, [.digit(1), .digit(7), .digit(6), .decimalSeparator, .digit(9), .digit(6)],
         [.digit(1), .digit(7), .digit(6), .decimalSeparator, .digit(9), .digit(7)]),
    ])
    func `The balance is the limit`(token: PaymentToken, within: [KeypadKey], past: [KeypadKey]) {
        let atLimit = Self.payment(in: token)
        Self.type(within, into: atLimit)
        #expect(atLimit.canSend)
        let pastLimit = Self.payment(in: token)
        Self.type(past, into: pastLimit)
        #expect(pastLimit.exceedsBalance)
        #expect(!pastLimit.canSend)
    }

    /// Every key press is counted, and a rejected one is also counted as a rejection, so the screen can signal it;
    /// the next accepted key clears the rejection.
    @Test func `Key presses and rejections are counted`() {
        let payment = Self.payment()
        Self.type([.decimalSeparator, .decimalSeparator], into: payment)
        #expect(payment.pressCount == 2)
        #expect(payment.rejectionCount == 1)
        #expect(payment.rejection == .key)
        payment.press(.digit(5))
        #expect(payment.rejection == nil)
    }

    /// A currency without minor units, such as yen, has no decimal separator.
    @Test func `A currency without minor units rejects the separator`() {
        let payment = Self.payment(currencyCode: "JPY")
        payment.press(.decimalSeparator)
        #expect(payment.rejectionCount == 1)
        #expect(payment.rejection == .key)
        #expect(payment.entry == AmountEntry(maximumFractionDigits: 0))
    }

    /// An amount starts over in tokens when it can't carry over: a dollar amount to a token without a price, or a
    /// quantity of one token to another, since it means nothing there.
    /// - Parameters:
    ///   - unit: The unit the amount is typed in.
    ///   - token: The token chosen next.
    @Test(arguments: [(PaymentModel.Unit.currency, unpriced), (.token, usdc)])
    func `An amount that can't carry over starts over in tokens`(unit: PaymentModel.Unit, token: PaymentToken) {
        let payment = Self.payment()
        payment.unitChoice = unit
        Self.type([.digit(5)], into: payment)
        payment.tokenChoice = token
        #expect(payment.unit == .token)
        #expect(payment.entry == AmountEntry(maximumFractionDigits: token.decimals))
    }

    /// A dollar amount carries over to another token with a price.
    @Test func `A currency amount carries over to a priced token`() {
        let payment = Self.payment()
        Self.type([.digit(5)], into: payment)
        payment.tokenChoice = Self.usdc
        #expect(payment.unit == .currency)
        #expect(payment.quantity == 5)
    }

    /// Switching to tokens converts what's typed, rounded down, and switching back returns the dollars as typed,
    /// cents included.
    @Test func `Switching units converts the amount`() {
        let payment = Self.payment()
        Self.type([.digit(1), .digit(2), .decimalSeparator, .digit(5), .digit(0)], into: payment)
        payment.unitChoice = .token
        #expect(payment.unit == .token)
        #expect(payment.entry.value == Decimal(string: "0.086883992"))
        payment.unitChoice = .currency
        #expect(payment.entry.value == Decimal(string: "12.5"))
        #expect(payment.entry.fractionDigits == "50")
    }

    /// Switching a token amount to dollars rounds to the nearest cent unless that buys more tokens than were typed, so
    /// the payment never grows and an amount within the balance stays within it.
    /// - Parameters:
    ///   - token: The token the amount is typed in.
    ///   - keys: The token amount's keys.
    @Test(arguments: [
        (tiny, [KeypadKey.digit(2), .digit(5), .digit(0)]),
        (PaymentToken(symbol: "HALF", balance: Decimal(string: "1.23")!, price: Decimal(string: "143.875"),
                      decimals: 9),
         [.digit(1), .decimalSeparator, .digit(2), .digit(3)]),
    ])
    func `Switching to currency never grows the payment`(token: PaymentToken, keys: [KeypadKey]) {
        let payment = Self.payment(in: token)
        payment.unitChoice = .token
        Self.type(keys, into: payment)
        let typed = payment.quantity
        payment.unitChoice = .currency
        #expect(payment.unit == .currency)
        #expect(payment.quantity <= typed)
        #expect(!payment.exceedsBalance)
    }

    /// A conversion with more whole digits than the keypad types keeps the unit and amount, and signals a rejection.
    @Test func `A conversion too large to type is refused`() {
        let payment = Self.payment(in: Self.tiny)
        Self.type([.digit(2), .digit(5), .digit(0), .digit(0), .digit(0)], into: payment)
        payment.unitChoice = .token
        #expect(payment.unit == .currency)
        #expect(payment.entry.value == 25_000)
        #expect(payment.rejectionCount == 1)
        #expect(payment.rejection == .conversion)
    }

    /// The person chooses a token among several, or a unit for a token with a price; one token without a price
    /// leaves nothing to choose.
    /// - Parameters:
    ///   - tokens: The tokens the account can pay with.
    ///   - offersChoices: Whether the payment offers a choice.
    @Test(arguments: [
        ([Self.sol, Self.unpriced], true),
        ([Self.sol], true),
        ([Self.unpriced], false),
    ])
    func `Only a payment with another token or unit offers choices`(tokens: [PaymentToken], offersChoices: Bool) {
        #expect(PaymentModel(tokens: tokens, currencyCode: "USD").offersChoices == offersChoices)
    }
}
