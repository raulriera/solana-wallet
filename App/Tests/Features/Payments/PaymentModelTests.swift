import Foundation
import Observation
import Synchronization
import Testing
import Transactions
@testable import widgets

@MainActor
struct PaymentModelTests {
    nonisolated private static let sol = PaymentToken(
        asset: .nativeSOL,
        balance: TokenAmount(amount: 1_230_000_000, decimals: 9), price: Decimal(string: "143.87"))
    nonisolated private static let usdc = PaymentFixtures.usdcToken
    nonisolated private static let unpriced = PaymentFixtures.token(
        PaymentFixtures.unpriced, decimals: 5, symbol: "NOPRICE", balance: 100_000_000, price: nil)
    nonisolated private static let otherUnpriced = PaymentFixtures.token(
        PaymentFixtures.half, decimals: 6, symbol: "UNLISTED", balance: 25_000_000, price: nil)
    nonisolated private static let tiny = PaymentFixtures.token(
        PaymentFixtures.tiny, decimals: 5, symbol: "TINY", balance: 1_000_000_000_000_000,
        price: Decimal(string: "0.00002"))

    private static func payment(in token: PaymentToken, currencyCode: String = "USD") -> PaymentModel {
        PaymentModel(tokens: [token] + [sol, usdc, unpriced, tiny].filter { $0 != token }, currencyCode: currencyCode)
    }

    private static func type(_ keys: [KeypadKey], into payment: PaymentModel) {
        keys.forEach(payment.press)
    }

    @Test func `A currency amount converts to tokens`() {
        let payment = Self.payment(in: Self.sol)
        Self.type([.digit(1), .digit(2)], into: payment)
        #expect(payment.value == 12)
        #expect(payment.quantity == Decimal(string: "0.083408632"))
        #expect(payment.canSend)
    }

    @Test(arguments: [
        (sol, [KeypadKey.digit(1), .digit(2)], TokenAmount(amount: 83_408_632, decimals: 9), Decimal?.some(12)),
        (usdc, [.digit(2), .decimalSeparator, .digit(5)], TokenAmount(amount: 2_500_000, decimals: 6),
         Decimal(string: "2.5")),
        (unpriced, [.digit(1), .decimalSeparator, .digit(5)], TokenAmount(amount: 150_000, decimals: 5), nil),
    ])
    func `The typed amount is sent in the token's decimals with its value`(token: PaymentToken, keys: [KeypadKey],
                                                                         sent: TokenAmount, value: Decimal?) {
        let payment = Self.payment(in: token)
        Self.type(keys, into: payment)
        #expect(payment.sent == sent)
        #expect(payment.value == value)
    }

    @Test func `An empty amount can't be sent`() {
        #expect(!Self.payment(in: Self.sol).canSend)
    }

    @Test func `An amount below the token's smallest unit can't be sent`() {
        let coarse = PaymentFixtures.token(
            PaymentFixtures.coarse, decimals: 2, symbol: "COARSE", balance: 1_000, price: 100_000)
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
        (PaymentFixtures.token(
            PaymentFixtures.half, decimals: 6, symbol: "HALF", balance: 1_000_000, price: Decimal(string: "0.999")),
         [.decimalSeparator, .digit(9), .digit(9)], [.digit(1)]),
        (PaymentFixtures.token(PaymentFixtures.coarse, decimals: 2, symbol: "COARSE", balance: 100, price: 50),
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
        let payment = Self.payment(in: Self.sol)
        Self.type([.decimalSeparator, .decimalSeparator], into: payment)
        #expect(payment.pressCount == 2)
        #expect(payment.rejectionCount == 1)
        #expect(payment.rejection == .key)
        payment.press(.digit(5))
        #expect(payment.rejection == nil)
    }

    @Test func `A currency without minor units rejects the separator`() {
        let payment = Self.payment(in: Self.sol, currencyCode: "JPY")
        payment.press(.decimalSeparator)
        #expect(payment.rejectionCount == 1)
        #expect(payment.rejection == .key)
        #expect(payment.entry == AmountEntry(maximumFractionDigits: 0))
    }

    @Test(arguments: [(PaymentModel.Unit.currency, unpriced), (.token, usdc)])
    func `An amount that can't carry over starts over in tokens`(unit: PaymentModel.Unit, token: PaymentToken) {
        let payment = Self.payment(in: Self.sol)
        payment.unitChoice = unit
        Self.type([.digit(5)], into: payment)
        payment.tokenChoice = token
        #expect(payment.unit == .token)
        #expect(payment.entry == AmountEntry(maximumFractionDigits: Int(token.balance.decimals)))
    }

    @Test func `A currency amount carries over to a priced token`() {
        let payment = Self.payment(in: Self.sol)
        Self.type([.digit(5)], into: payment)
        payment.tokenChoice = Self.usdc
        #expect(payment.unit == .currency)
        #expect(payment.quantity == 5)
    }

    @Test func `Switching units converts the amount`() {
        let payment = Self.payment(in: Self.sol)
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
        (PaymentFixtures.token(
            PaymentFixtures.half, decimals: 9, symbol: "HALF", balance: 1_230_000_000,
            price: Decimal(string: "143.875")),
         [.digit(1), .decimalSeparator, .digit(2), .digit(3)]),
        (PaymentFixtures.token(
            PaymentFixtures.coarse, decimals: 2, symbol: "COARSE", balance: 100, price: Decimal(string: "50.006")),
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
        let richer = PaymentFixtures.token(
            PaymentFixtures.usdc, decimals: 6, symbol: "USDC", balance: 100_000_000, price: 1)

        payment.update([Self.sol, richer], currencyCode: "USD")

        #expect(payment.token == richer)
        #expect(payment.tokens == [Self.sol, richer])
        #expect(payment.unit == .currency)
        #expect(payment.entry.value == 12)
    }

    @Test func `Updates follow the selected token's mint, not its symbol`() {
        let payment = Self.payment(in: Self.usdc)
        let lookAlike = PaymentFixtures.token(
            PaymentFixtures.lookAlike, decimals: 6, symbol: "USDC", balance: 5_000_000, price: 1)

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
        let payment = Self.payment(in: Self.sol)
        Self.type([.digit(1), .digit(2)], into: payment)
        let typed = payment.quantity
        let unpricedSOL = PaymentToken(
            asset: .nativeSOL,
            balance: TokenAmount(amount: 1_230_000_000, decimals: 9), price: nil)

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
        let payment = Self.payment(in: Self.sol)
        Self.type([.digit(1), .digit(2)], into: payment)
        let euroSOL = PaymentToken(
            asset: .nativeSOL,
            balance: TokenAmount(amount: 1_230_000_000, decimals: 9), price: 120)

        payment.update([euroSOL, Self.usdc], currencyCode: "EUR")

        #expect(payment.currencyCode == "EUR")
        #expect(payment.token == euroSOL)
        #expect(payment.unit == .currency)
        #expect(payment.entry.value == 0)
    }

    @Test func `A currency change keeps a token amount`() {
        let payment = Self.payment(in: Self.sol)
        payment.unitChoice = .token
        Self.type([.digit(1)], into: payment)
        let euroSOL = PaymentToken(
            asset: .nativeSOL,
            balance: TokenAmount(amount: 1_230_000_000, decimals: 9), price: 120)

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
