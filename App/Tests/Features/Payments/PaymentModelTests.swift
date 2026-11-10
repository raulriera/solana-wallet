import Foundation
import Observation
import Synchronization
import Testing
@testable import widgets

@MainActor
struct PaymentModelTests {
    nonisolated private static let sol = PaymentToken(mint: nil, symbol: "SOL", balance: Decimal(string: "1.23")!,
                                                      price: Decimal(string: "143.87"), decimals: 9)
    nonisolated private static let usdc = PaymentToken(mint: PaymentFixtures.usdc, symbol: "USDC", balance: 40,
                                                       price: 1, decimals: 6)
    nonisolated private static let unpriced = PaymentToken(mint: PaymentFixtures.unpriced, symbol: "NOPRICE",
                                                           balance: 1_000, price: nil, decimals: 5)
    nonisolated private static let otherUnpriced = PaymentToken(mint: PaymentFixtures.half, symbol: "UNLISTED",
                                                                balance: 25, price: nil, decimals: 6)
    nonisolated private static let tiny = PaymentToken(mint: PaymentFixtures.tiny, symbol: "TINY",
                                                       balance: 10_000_000_000, price: Decimal(string: "0.00002"),
                                                       decimals: 5)

    private static func payment(in token: PaymentToken = sol, currencyCode: String = "USD") -> PaymentModel {
        PaymentModel(tokens: [token] + [sol, usdc, unpriced, tiny].filter { $0 != token }, currencyCode: currencyCode)
    }

    private static func type(_ keys: [KeypadKey], into payment: PaymentModel) {
        keys.forEach(payment.press)
    }

    @Test func `A currency amount converts to tokens`() {
        let payment = Self.payment()
        Self.type([.digit(1), .digit(2)], into: payment)
        #expect(payment.value == 12)
        #expect(payment.quantity == Decimal(string: "0.083408632"))
        #expect(payment.canSend)
    }

    @Test func `An empty amount can't be sent`() {
        #expect(!Self.payment().canSend)
    }

    @Test func `An amount below the token's smallest unit can't be sent`() {
        let coarse = PaymentToken(mint: PaymentFixtures.coarse, symbol: "COARSE", balance: 10, price: 100_000,
                                  decimals: 2)
        let payment = Self.payment(in: coarse)
        Self.type([.decimalSeparator, .digit(5), .digit(0)], into: payment)
        #expect(payment.value == Decimal(string: "0.5"))
        #expect(payment.quantity == 0)
        #expect(!payment.canSend)
    }

    @Test(arguments: [
        (unpriced, [KeypadKey.digit(1), .digit(0), .digit(0), .digit(0)],
         [KeypadKey.digit(1), .digit(0), .digit(0), .digit(0), .decimalSeparator, .digit(0), .digit(0), .digit(0),
          .digit(0), .digit(1)]),
        (sol, [.digit(1), .digit(7), .digit(6), .decimalSeparator, .digit(9), .digit(6)],
         [.digit(1), .digit(7), .digit(6), .decimalSeparator, .digit(9), .digit(7)]),
        (PaymentToken(mint: PaymentFixtures.half, symbol: "HALF", balance: 1, price: Decimal(string: "0.999"),
                      decimals: 6),
         [.decimalSeparator, .digit(9), .digit(9)], [.digit(1)]),
        (PaymentToken(mint: PaymentFixtures.coarse, symbol: "COARSE", balance: 1, price: 50, decimals: 2),
         [.digit(5), .digit(0)], [.digit(5), .digit(0), .decimalSeparator, .digit(4), .digit(9)]),
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

    @Test func `Key presses and rejections are counted`() {
        let payment = Self.payment()
        Self.type([.decimalSeparator, .decimalSeparator], into: payment)
        #expect(payment.pressCount == 2)
        #expect(payment.rejectionCount == 1)
        #expect(payment.rejection == .key)
        payment.press(.digit(5))
        #expect(payment.rejection == nil)
    }

    @Test func `A currency without minor units rejects the separator`() {
        let payment = Self.payment(currencyCode: "JPY")
        payment.press(.decimalSeparator)
        #expect(payment.rejectionCount == 1)
        #expect(payment.rejection == .key)
        #expect(payment.entry == AmountEntry(maximumFractionDigits: 0))
    }

    @Test(arguments: [(PaymentModel.Unit.currency, unpriced), (.token, usdc)])
    func `An amount that can't carry over starts over in tokens`(unit: PaymentModel.Unit, token: PaymentToken) {
        let payment = Self.payment()
        payment.unitChoice = unit
        Self.type([.digit(5)], into: payment)
        payment.tokenChoice = token
        #expect(payment.unit == .token)
        #expect(payment.entry == AmountEntry(maximumFractionDigits: token.decimals))
    }

    @Test func `A currency amount carries over to a priced token`() {
        let payment = Self.payment()
        Self.type([.digit(5)], into: payment)
        payment.tokenChoice = Self.usdc
        #expect(payment.unit == .currency)
        #expect(payment.quantity == 5)
    }

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

    @Test(arguments: [
        (tiny, [KeypadKey.digit(2), .digit(5), .digit(0)]),
        (PaymentToken(mint: PaymentFixtures.half, symbol: "HALF", balance: Decimal(string: "1.23")!,
                      price: Decimal(string: "143.875"),
                      decimals: 9),
         [.digit(1), .decimalSeparator, .digit(2), .digit(3)]),
        (PaymentToken(mint: PaymentFixtures.coarse, symbol: "COARSE", balance: 1, price: Decimal(string: "50.006"),
                      decimals: 2),
         [.digit(1)]),
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

    @Test func `A conversion too large to type is refused`() {
        let payment = Self.payment(in: Self.tiny)
        Self.type([.digit(2), .digit(5), .digit(0), .digit(0), .digit(0)], into: payment)
        payment.unitChoice = .token
        #expect(payment.unit == .currency)
        #expect(payment.entry.value == 25_000)
        #expect(payment.rejectionCount == 1)
        #expect(payment.rejection == .conversion)
    }

    @Test(arguments: [
        ([Self.sol, Self.unpriced], true),
        ([Self.unpriced, Self.otherUnpriced], true),
        ([Self.sol], true),
        ([Self.unpriced], false),
    ])
    func `Only a payment with another token or unit offers choices`(tokens: [PaymentToken], offersChoices: Bool) {
        #expect(PaymentModel(tokens: tokens, currencyCode: "USD").offersChoices == offersChoices)
    }

    @Test func `New balances keep the selected token and amount`() {
        let payment = Self.payment(in: Self.usdc)
        Self.type([.digit(1), .digit(2)], into: payment)
        let richer = PaymentToken(mint: PaymentFixtures.usdc, symbol: "USDC", balance: 100, price: 1, decimals: 6)

        payment.update([Self.sol, richer], currencyCode: "USD")

        #expect(payment.token == richer)
        #expect(payment.tokens == [Self.sol, richer])
        #expect(payment.unit == .currency)
        #expect(payment.entry.value == 12)
    }

    @Test func `Updates follow the selected token's mint, not its symbol`() {
        let payment = Self.payment(in: Self.usdc)
        let lookAlike = PaymentToken(mint: PaymentFixtures.lookAlike, symbol: "USDC", balance: 5, price: 1, decimals: 6)

        payment.update([lookAlike, Self.usdc], currencyCode: "USD")

        #expect(payment.token == Self.usdc)
    }

    @Test func `A token that's gone selects the first token`() {
        let payment = Self.payment(in: Self.usdc)
        Self.type([.digit(1), .digit(2)], into: payment)

        payment.update([Self.unpriced, Self.sol], currencyCode: "USD")

        #expect(payment.token == Self.unpriced)
        #expect(payment.unit == .token)
        #expect(payment.entry.value == 0)
    }

    @Test func `A token that loses its price keeps the quantity in tokens`() {
        let payment = Self.payment()
        Self.type([.digit(1), .digit(2)], into: payment)
        let typed = payment.quantity
        let unpricedSOL = PaymentToken(mint: nil, symbol: "SOL", balance: Decimal(string: "1.23")!, price: nil,
                                       decimals: 9)

        payment.update([unpricedSOL], currencyCode: "USD")

        #expect(payment.unit == .token)
        #expect(payment.quantity == typed)
        #expect(payment.value == nil)
    }

    @Test func `The same tokens change nothing`() {
        let tokens = [Self.sol, Self.usdc]
        let payment = PaymentModel(tokens: tokens, currencyCode: "USD")
        let changed = Mutex(false)
        withObservationTracking { _ = payment.tokens } onChange: { changed.withLock { $0 = true } }

        payment.update(tokens, currencyCode: "USD")

        let notified = changed.withLock(\.self)
        #expect(!notified)
    }

    @Test func `A currency change starts a currency amount again`() {
        let payment = Self.payment()
        Self.type([.digit(1), .digit(2)], into: payment)
        let euroSOL = PaymentToken(mint: nil, symbol: "SOL", balance: Decimal(string: "1.23")!, price: 120, decimals: 9)

        payment.update([euroSOL, Self.usdc], currencyCode: "EUR")

        #expect(payment.currencyCode == "EUR")
        #expect(payment.token == euroSOL)
        #expect(payment.unit == .currency)
        #expect(payment.entry.value == 0)
    }

    @Test func `A currency change keeps a token amount`() {
        let payment = Self.payment()
        payment.unitChoice = .token
        Self.type([.digit(1)], into: payment)
        let euroSOL = PaymentToken(mint: nil, symbol: "SOL", balance: Decimal(string: "1.23")!, price: 120, decimals: 9)

        payment.update([euroSOL, Self.usdc], currencyCode: "EUR")

        #expect(payment.unit == .token)
        #expect(payment.quantity == 1)
        #expect(payment.value == 120)
    }

    @Test func `Clearing keeps the token and unit`() {
        let payment = Self.payment(in: Self.usdc)
        Self.type([.digit(1), .digit(2)], into: payment)

        payment.clear()

        #expect(payment.entry.value == 0)
        #expect(payment.token == Self.usdc)
        #expect(payment.unit == .currency)
    }

    @Test(arguments: [
        ([Self.unpriced], PaymentModel.Unit.token, "USD", Decimal(1_000)),
        ([Self.sol, Self.usdc], .token, "USD", Decimal(string: "1.23")!),
        ([Self.sol, Self.usdc], .currency, "USD", Decimal(string: "176.96")!),
        ([Self.sol, Self.usdc], .currency, "JPY", 176),
    ])
    func `The balance is in the unit the amount is typed in`(tokens: [PaymentToken], unit: PaymentModel.Unit,
                                                              currencyCode: String, balance: Decimal) throws {
        let payment = PaymentModel(tokens: tokens, currencyCode: currencyCode)
        payment.unitChoice = unit
        try #require(payment.unit == unit)
        #expect(payment.entryBalance == balance)
    }

    @Test(arguments: [
        (PaymentModel.Unit.token, "Balance: 1.23 SOL"),
        (.currency, "Balance: $176.96"),
    ])
    func `The balance line shows the balance in the unit the amount is typed in`(unit: PaymentModel.Unit,
                                                                                  text: String) {
        let payment = PaymentModel(tokens: [Self.sol, Self.usdc], currencyCode: "USD")
        payment.unitChoice = unit
        var balance = payment.balanceText
        balance.locale = Locale(identifier: "en_US")
        #expect(String(localized: balance) == text)
    }
}
