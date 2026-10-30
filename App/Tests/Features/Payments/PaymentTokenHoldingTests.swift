import Foundation
import Portfolio
import Testing
import Transactions
@testable import widgets

struct PaymentTokenHoldingTests {
    nonisolated private static let dollars = Valuation(pricePerUnit: 2, total: nil, currency: "USD")

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

    @Test func `A price in another currency is left out`() throws {
        let holding = Holding(id: .nativeSOL, amount: Amount(units: 1, decimals: 9), name: nil, symbol: "SOL",
                              imageURL: nil, valuation: Self.dollars)

        let token = try #require(PaymentToken(holding: holding, currencyCode: "EUR"))

        #expect(token.price == nil)
    }
}
