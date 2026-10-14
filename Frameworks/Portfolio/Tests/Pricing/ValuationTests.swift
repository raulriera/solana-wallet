import Foundation
import RPC
import Testing
@testable import Portfolio

/// Checks provider-neutral decimal valuation independently of HTTP response formats.
struct ValuationTests {
    /// Verifies exact totals and explicit unknowns at Decimal's representational limits.
    /// - Parameters:
    ///   - amount: The known or unavailable token quantity.
    ///   - price: The price of one whole token in the provider's currency.
    ///   - total: The expected total, or `nil` when it cannot be represented exactly.
    /// - Throws: A pricing or test prerequisite error.
    @Test(arguments: [
        (Amount(units: .max, decimals: 6), Decimal(string: "0.1")!, Decimal(string: "1844674407370.9551615")),
        (Amount(units: 1, decimals: 9), Decimal(string: "123.456789")!, Decimal(string: "0.000000123456789")),
        (Amount(units: 0, decimals: .max), Decimal(10), Decimal(0)),
        (Amount(units: 1, decimals: .max), Decimal(0), Decimal(0)),
        (Amount(units: 1, decimals: .max), Decimal(10), nil),
        (Amount(units: .max, decimals: 0), Decimal.greatestFiniteMagnitude, nil),
        (nil, Decimal(10), nil),
    ])
    func `Valuation preserves decimal precision and never invents unrepresentable totals`(amount: Amount?, price: Decimal, total: Decimal?) async throws {
        let retrieved = Date(timeIntervalSince1970: 20)
        let quote = Quote(pricePerUnit: price, currency: "CAD", fetchedAt: retrieved)
        let snapshot = Snapshot(owner: "wallet", network: .devnet, holdings: [
            Holding(id: .asset("mint"), amount: amount, name: "Token", symbol: "TOK", imageURL: nil, valuation: nil),
        ], fetchedAt: .distantPast)
        let result = try await valued(snapshot, with: FixedPrices(quote: quote))
        let valuation = try #require(result.holdings.first?.valuation)
        #expect(valuation.pricePerUnit == price)
        #expect(valuation.total == total)
        #expect(valuation.currency == "CAD")
        #expect(valuation.fetchedAt == retrieved)
        #expect(result.fetchedAt == snapshot.fetchedAt)
    }

    /// Verifies malformed normalized quotes cannot enter cached portfolio values.
    /// - Parameter quote: A quote violating the provider-neutral value contract.
    @Test(arguments: [
        Quote(pricePerUnit: -1, currency: "USD", fetchedAt: .now),
        Quote(pricePerUnit: .nan, currency: "USD", fetchedAt: .now),
        Quote(pricePerUnit: 1, currency: " ", fetchedAt: .now),
        Quote(pricePerUnit: 1, currency: "USD", fetchedAt: Date(timeIntervalSince1970: .infinity)),
    ])
    func `Invalid independent quotes fail valuation`(quote: Quote) async {
        let snapshot = Snapshot(owner: "wallet", network: .devnet, holdings: [
            Holding(id: .asset("mint"), amount: nil, name: nil, symbol: nil, imageURL: nil, valuation: nil),
        ], fetchedAt: .distantPast)
        await #expect(throws: PriceError.invalidQuote) {
            try await valued(snapshot, with: FixedPrices(quote: quote))
        }
    }

    /// Verifies a valuation keeps the quote's 24-hour change, including an unknown one.
    /// - Parameter change: The quote's 24-hour change, or `nil` when the provider has none.
    /// - Throws: A pricing or test prerequisite error.
    @Test(arguments: [Decimal(string: "0.0129"), nil])
    func `Valuations keep the quote's 24-hour change`(change: Decimal?) async throws {
        let valuation = try await pricedValuation(dayChange: change)
        #expect(valuation.total == 2)
        #expect(valuation.dayChange == change)
    }

    /// Verifies a change that isn't a number stays unknown while the price is kept.
    /// - Throws: A pricing or test prerequisite error.
    @Test
    func `A 24-hour change that isn't a number stays unknown`() async throws {
        let valuation = try await pricedValuation(dayChange: .nan)
        #expect(valuation.total == 2)
        #expect(valuation.dayChange == nil)
    }

    /// Verifies a valuation saved before the 24-hour change existed still loads, with the change unknown.
    /// - Throws: A decoding error.
    @Test
    func `Saved valuations without a 24-hour change still load`() throws {
        let saved = Data(#"{"pricePerUnit":2,"total":4,"currency":"USD"}"#.utf8)
        let valuation = try JSONDecoder().decode(Valuation.self, from: saved)
        #expect(valuation.total == 4)
        #expect(valuation.dayChange == nil)
    }

    /// Prices one unit of a token at 2 USD with the given 24-hour change.
    /// - Parameter dayChange: The quote's 24-hour change.
    /// - Returns: The token's valuation.
    /// - Throws: A pricing or test prerequisite error.
    private func pricedValuation(dayChange: Decimal?) async throws -> Valuation {
        let quote = Quote(pricePerUnit: 2, currency: "USD", fetchedAt: .now, dayChange: dayChange)
        let snapshot = Snapshot(owner: "wallet", network: .devnet, holdings: [
            Holding(id: .asset("mint"), amount: Amount(units: 1, decimals: 0), name: nil, symbol: nil, imageURL: nil,
                    valuation: nil),
        ], fetchedAt: .distantPast)
        let result = try await valued(snapshot, with: FixedPrices(quote: quote))
        return try #require(result.holdings.first?.valuation)
    }

    /// Prices a snapshot the way a refresh does: one quote lookup for its holdings, then valuation.
    /// - Parameters:
    ///   - snapshot: The holdings to value.
    ///   - provider: The quote source.
    /// - Returns: The holdings with their valuations.
    /// - Throws: A pricing error.
    private func valued(_ snapshot: Snapshot, with provider: any PriceProviding) async throws -> Snapshot {
        let pricer = SnapshotPricer(provider: provider)
        return try pricer.snapshot(pricing: snapshot, with: await pricer.quotes(for: snapshot.holdings.map(\.id)))
    }
}

/// An alternate normalized provider proving valuation does not depend on Jupiter's format or currency.
private struct FixedPrices: PriceProviding {
    let network: Network = .devnet
    let quote: Quote

    /// Supplies a deterministic quote for pure valuation checks, without RPC communication.
    /// - Parameter mints: The requested token markets.
    /// - Returns: The normalized quote for each requested mint.
    func prices(for mints: [String]) async throws -> [String: Quote] {
        Dictionary(uniqueKeysWithValues: mints.map { ($0, quote) })
    }
}
