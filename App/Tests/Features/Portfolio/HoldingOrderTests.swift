import Foundation
import Portfolio
import Testing
import Transactions
@testable import widgets

struct HoldingOrderTests {
    @Test
    func `Known values lead from high to low, then unknown values`() {
        let holdings = [token("unpriced"), token("low", value: 1), solana(), token("high", value: 5)]
        let order = HoldingOrder.sorted(holdings).map(\.asset.displaySymbol)
        #expect(order == ["high", "low", "unpriced", "SOL"])
    }

    @Test
    func `Equal values keep the provider's order`() {
        let holdings = [token("c", value: 2), token("a", value: 2), token("b", value: 2)]
        #expect(HoldingOrder.sorted(holdings).map(\.asset.displaySymbol) == ["c", "a", "b"])
    }

    @Test
    func `Mixed quote currencies keep the provider's order`() {
        let holdings = [token("usd", value: 1, currency: "USD"), token("eur", value: 9, currency: "EUR"), solana()]
        #expect(HoldingOrder.sorted(holdings).map(\.asset.displaySymbol) == ["usd", "eur", "SOL"])
    }

    private func solana() -> Holding {
        Holding(asset: .nativeSOL, balance: TokenAmount(lamports: 0), imageURL: nil, valuation: nil)
    }

    private func token(_ symbol: String, value: Decimal? = nil, currency: String = "USD") -> Holding {
        Holding.fixture(.fixture(symbol: symbol), amount: 1,
                        valuation: value.map { Valuation(pricePerUnit: $0, total: $0, currency: currency) })
    }
}
