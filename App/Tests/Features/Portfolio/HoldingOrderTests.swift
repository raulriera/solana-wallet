import Foundation
import Portfolio
import Testing
@testable import widgets

struct HoldingOrderTests {
    @Test
    func `Known values lead from high to low, then unknown values`() {
        let holdings = [token("unpriced"), token("low", value: 1), solana(), token("high", value: 5)]
        let order = HoldingOrder.sorted(holdings).map(\.id)
        #expect(order == [.asset("high"), .asset("low"), .asset("unpriced"), .nativeSOL])
    }

    @Test
    func `Native SOL sorts by its value like any other token`() {
        let holdings = [solana(value: 3), token("low", value: 1), token("high", value: 5)]
        #expect(HoldingOrder.sorted(holdings).map(\.id) == [.asset("high"), .nativeSOL, .asset("low")])
    }

    @Test
    func `Equal values keep the provider's order`() {
        let holdings = [token("c", value: 2), token("a", value: 2), token("b", value: 2)]
        #expect(HoldingOrder.sorted(holdings).map(\.id) == [.asset("c"), .asset("a"), .asset("b")])
    }

    @Test
    func `Mixed quote currencies keep the provider's order`() {
        let holdings = [token("usd", value: 1, currency: "USD"), token("eur", value: 9, currency: "EUR"), solana()]
        #expect(HoldingOrder.sorted(holdings).map(\.id) == [.asset("usd"), .asset("eur"), .nativeSOL])
    }

    private func solana(value: Decimal? = nil) -> Holding {
        Holding(id: .nativeSOL, amount: Amount(units: 0, decimals: 9), name: "Solana", symbol: "SOL", imageURL: nil,
                valuation: value.map { Valuation(pricePerUnit: $0, total: $0, currency: "USD") })
    }

    private func token(_ id: String, value: Decimal? = nil, currency: String = "USD") -> Holding {
        Holding(id: .asset(id), amount: Amount(units: 1, decimals: 0), name: nil, symbol: nil, imageURL: nil,
                valuation: value.map { Valuation(pricePerUnit: $0, total: $0, currency: currency) })
    }
}
