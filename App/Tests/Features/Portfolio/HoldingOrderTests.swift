import Foundation
import Portfolio
import Testing
@testable import widgets

/// Checks the portfolio's display order without comparing different currencies.
struct HoldingOrderTests {
    /// Known values lead from high to low, and unknown values follow in the provider's order, native SOL included.
    @Test
    func `Known values lead from high to low, then unknown values`() {
        let holdings = [token("unpriced"), token("low", value: 1), solana(), token("high", value: 5)]
        let order = HoldingOrder.sorted(holdings).map(\.id)
        #expect(order == [.asset("high"), .asset("low"), .asset("unpriced"), .nativeSOL])
    }

    /// Native SOL takes the place of its value instead of always coming first.
    @Test
    func `Native SOL sorts by its value like any other token`() {
        let holdings = [solana(value: 3), token("low", value: 1), token("high", value: 5)]
        #expect(HoldingOrder.sorted(holdings).map(\.id) == [.asset("high"), .nativeSOL, .asset("low")])
    }

    /// Equal values keep the provider's order instead of an arbitrary one.
    @Test
    func `Equal values keep the provider's order`() {
        let holdings = [token("c", value: 2), token("a", value: 2), token("b", value: 2)]
        #expect(HoldingOrder.sorted(holdings).map(\.id) == [.asset("c"), .asset("a"), .asset("b")])
    }

    /// Values in different currencies can't be compared, so every holding keeps the provider's order.
    @Test
    func `Mixed quote currencies keep the provider's order`() {
        let holdings = [token("usd", value: 1, currency: "USD"), token("eur", value: 9, currency: "EUR"), solana()]
        #expect(HoldingOrder.sorted(holdings).map(\.id) == [.asset("usd"), .asset("eur"), .nativeSOL])
    }

    /// Creates native SOL.
    /// - Parameter value: The whole balance's USD value, or `nil` when unknown, as a new wallet reports it.
    /// - Returns: A native SOL holding.
    private func solana(value: Decimal? = nil) -> Holding {
        Holding(id: .nativeSOL, amount: Amount(units: 0, decimals: 9), name: "Solana", symbol: "SOL", imageURL: nil,
                valuation: value.map { Valuation(pricePerUnit: $0, total: $0, currency: "USD") })
    }

    /// Creates a fungible token holding.
    /// - Parameters:
    ///   - id: The token's mint address.
    ///   - value: The whole holding's value, or `nil` when unknown.
    ///   - currency: The value's quote currency.
    /// - Returns: A holding of one unit with the given value.
    private func token(_ id: String, value: Decimal? = nil, currency: String = "USD") -> Holding {
        Holding(id: .asset(id), amount: Amount(units: 1, decimals: 0), name: nil, symbol: nil, imageURL: nil,
                valuation: value.map { Valuation(pricePerUnit: $0, total: $0, currency: currency) })
    }
}
