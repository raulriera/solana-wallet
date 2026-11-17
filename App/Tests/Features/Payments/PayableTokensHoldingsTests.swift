import Foundation
import Portfolio
import Testing
import Transactions
@testable import widgets

@MainActor
struct PayableTokensHoldingsTests {
    private static let sol = Holding(asset: .nativeSOL, balance: TokenAmount(lamports: 1_500_000_000),
                                     imageURL: nil,
                                     valuation: Valuation(pricePerUnit: 150, total: nil, currency: "USD"))
    private static let empty = Holding.fixture(.fixture(PaymentFixtures.usdc.value, decimals: 6), amount: 0)
    private static let unpriced = Holding.fixture(
        .fixture(PaymentFixtures.unpriced.value, decimals: 1, symbol: "NOPRICE"), amount: 25)

    @Test func `A portfolio that hasn't loaded has no tokens yet`() {
        #expect(PayableTokens(holdings: [], error: nil) == nil)
    }

    @Test func `Only holdings with a balance are tokens`() {
        let payable = PayableTokens(holdings: [Self.sol, Self.empty, Self.unpriced], error: nil)

        #expect(payable == PayableTokens(tokens: [
            PaymentToken(asset: .nativeSOL, balance: TokenAmount(lamports: 1_500_000_000), price: 150),
            PaymentFixtures.token(PaymentFixtures.unpriced, decimals: 1, symbol: "NOPRICE", balance: 25, price: nil),
        ], currencyCode: "USD"))
    }

    @Test func `The keypad types the currency of the prices`() {
        let payable = PayableTokens(holdings: [
            Self.unpriced,
            Holding(asset: .nativeSOL, balance: TokenAmount(lamports: 1_500_000_000),
                    imageURL: nil, valuation: Valuation(pricePerUnit: 120, total: nil, currency: "EUR")),
        ], error: nil)

        #expect(payable?.currencyCode == "EUR")
        #expect(payable?.tokens.last?.price == 120)
    }

    @Test func `A portfolio that failed to load has no tokens`() {
        #expect(PayableTokens(holdings: [], error: .invalidKey)?.tokens == [])
    }
}
