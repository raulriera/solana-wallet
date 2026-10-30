import Foundation
import Portfolio
import Testing
import Transactions
@testable import widgets

@MainActor
struct PayableTokensHoldingsTests {
    private static let sol = Holding(id: .nativeSOL, amount: Amount(units: 1_500_000_000, decimals: 9), name: nil,
                                     symbol: "SOL", imageURL: nil,
                                     valuation: Valuation(pricePerUnit: 150, total: nil, currency: "USD"))
    private static let empty = Holding(id: .asset(PaymentFixtures.usdc.value), amount: Amount(units: 0, decimals: 6),
                                       name: nil, symbol: "USDC", imageURL: nil, valuation: nil)
    private static let unpriced = Holding(id: .asset(PaymentFixtures.unpriced.value),
                                          amount: Amount(units: 25, decimals: 1), name: nil, symbol: "NOPRICE",
                                          imageURL: nil, valuation: nil)

    @Test func `A portfolio that hasn't loaded has no tokens yet`() {
        #expect(PayableTokens(holdings: [], error: nil) == nil)
    }

    @Test func `Only holdings with a balance are tokens`() {
        let payable = PayableTokens(holdings: [Self.sol, Self.empty, Self.unpriced], error: nil)

        #expect(payable == PayableTokens(tokens: [
            PaymentToken(mint: nil, symbol: "SOL", balance: Decimal(string: "1.5")!, price: 150, decimals: 9),
            PaymentToken(mint: PaymentFixtures.unpriced, symbol: "NOPRICE", balance: Decimal(string: "2.5")!,
                         price: nil, decimals: 1),
        ], currencyCode: "USD"))
    }

    @Test func `The keypad types the currency of the prices`() {
        let payable = PayableTokens(holdings: [
            Self.unpriced,
            Holding(id: .nativeSOL, amount: Amount(units: 1_500_000_000, decimals: 9), name: nil, symbol: "SOL",
                    imageURL: nil, valuation: Valuation(pricePerUnit: 120, total: nil, currency: "EUR")),
        ], error: nil)

        #expect(payable?.currencyCode == "EUR")
        #expect(payable?.tokens.last?.price == 120)
    }

    @Test func `A portfolio that failed to load has no tokens`() {
        #expect(PayableTokens(holdings: [], error: .invalidKey)?.tokens == [])
    }
}
