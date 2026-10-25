import Foundation
import Portfolio
import Testing
import Transactions
@testable import widgets

/// Checks which of the account's holdings the keypad pays with, and what it keeps of each.
struct PaymentTokenHoldingTests {
    /// A dollar price for one token.
    nonisolated private static let dollars = Valuation(pricePerUnit: 2, total: nil, currency: "USD")

    /// A holding with a balance becomes a token with its mint, symbol, exact balance, decimals, and price; native SOL
    /// has no mint.
    /// - Parameters:
    ///   - holding: The holding in the portfolio.
    ///   - token: The token the keypad pays with.
    @Test(arguments: [
        (Holding(id: .asset(PaymentFixtures.usdc.value), amount: Amount(units: 1_234_567, decimals: 6),
                 name: "USD Coin", symbol: "USDC", imageURL: nil, valuation: dollars),
         PaymentToken(mint: PaymentFixtures.usdc, symbol: "USDC", balance: Decimal(string: "1.234567")!, price: 2,
                      decimals: 6)),
        (Holding(id: .nativeSOL, amount: Amount(units: 1, decimals: 9), name: nil, symbol: nil, imageURL: nil,
                 valuation: nil),
         PaymentToken(mint: nil, symbol: "SOL", balance: Decimal(string: "0.000000001")!, price: nil, decimals: 9)),
    ])
    func `A holding with a balance becomes a token`(holding: Holding, token: PaymentToken) {
        #expect(PaymentToken(holding: holding, currencyCode: "USD") == token)
    }

    /// Nothing to spend leaves a holding out: no balance, an unknown one, one that another address controls, or a mint
    /// that isn't a valid address.
    /// - Parameter holding: The holding in the portfolio.
    @Test(arguments: [
        Holding(id: .asset(PaymentFixtures.usdc.value), amount: Amount(units: 0, decimals: 6), name: nil,
                symbol: "USDC", imageURL: nil, valuation: nil),
        Holding(id: .asset(PaymentFixtures.usdc.value), amount: nil, name: nil, symbol: "USDC", imageURL: nil,
                valuation: nil),
        Holding(id: .asset(PaymentFixtures.usdc.value), amount: Amount(units: 5, decimals: 6),
                otherOwner: PaymentFixtures.lookAlike, name: nil, symbol: "USDC", imageURL: nil, valuation: nil),
        Holding(id: .asset("not-a-mint"), amount: Amount(units: 5, decimals: 0), name: nil, symbol: "BAD",
                imageURL: nil, valuation: nil),
    ])
    func `A holding with nothing to spend is left out`(holding: Holding) {
        #expect(PaymentToken(holding: holding, currencyCode: "USD") == nil)
    }

    /// A price in another currency than the person's is unknown to the keypad, so the amount is typed in tokens.
    /// - Throws: A test prerequisite error.
    @Test func `A price in another currency is left out`() throws {
        let holding = Holding(id: .nativeSOL, amount: Amount(units: 1, decimals: 9), name: nil, symbol: "SOL",
                              imageURL: nil, valuation: Self.dollars)

        let token = try #require(PaymentToken(holding: holding, currencyCode: "EUR"))

        #expect(token.price == nil)
    }
}
