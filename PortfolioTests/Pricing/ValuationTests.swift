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
    @Test("valuation preserves decimal precision and never invents unrepresentable totals", arguments: [
        (Amount(units: .max, decimals: 6), Decimal(string: "0.1")!, Decimal(string: "1844674407370.9551615")),
        (Amount(units: 1, decimals: 9), Decimal(string: "123.456789")!, Decimal(string: "0.000000123456789")),
        (Amount(units: 0, decimals: .max), Decimal(10), Decimal(0)),
        (Amount(units: 1, decimals: .max), Decimal(0), Decimal(0)),
        (Amount(units: 1, decimals: .max), Decimal(10), nil),
        (Amount(units: .max, decimals: 0), Decimal.greatestFiniteMagnitude, nil),
        (nil, Decimal(10), nil),
    ])
    func preservesDecimalTotals(amount: Amount?, price: Decimal, total: Decimal?) async throws {
        let retrieved = Date(timeIntervalSince1970: 20)
        let quote = Quote(pricePerUnit: price, currency: "CAD", fetchedAt: retrieved)
        let snapshot = Snapshot(owner: "wallet", network: .devnet, holdings: [
            Holding(id: .asset("mint"), amount: amount, name: "Token", symbol: "TOK", imageURL: nil, valuation: nil),
        ], fetchedAt: .distantPast, lastIndexedSlot: 123)
        let result = try await SnapshotPricer(provider: FixedPrices(quote: quote)).snapshot(pricing: snapshot)
        let valuation = try #require(result.holdings.first?.valuation)
        #expect(valuation.pricePerUnit == price)
        #expect(valuation.total == total)
        #expect(valuation.currency == "CAD")
        #expect(valuation.fetchedAt == retrieved)
        #expect(result.fetchedAt == snapshot.fetchedAt)
    }

    /// Verifies malformed normalized quotes cannot enter cached portfolio values.
    /// - Parameter quote: A quote violating the provider-neutral value contract.
    @Test("invalid independent quotes fail valuation", arguments: [
        Quote(pricePerUnit: -1, currency: "USD", fetchedAt: .now),
        Quote(pricePerUnit: .nan, currency: "USD", fetchedAt: .now),
        Quote(pricePerUnit: 1, currency: " ", fetchedAt: .now),
        Quote(pricePerUnit: 1, currency: "USD", fetchedAt: Date(timeIntervalSince1970: .infinity)),
    ])
    func rejectsInvalidQuotes(quote: Quote) async {
        let snapshot = Snapshot(owner: "wallet", network: .devnet, holdings: [
            Holding(id: .asset("mint"), amount: nil, name: nil, symbol: nil, imageURL: nil, valuation: nil),
        ], fetchedAt: .distantPast, lastIndexedSlot: nil)
        await #expect(throws: PriceError.invalidQuote) {
            try await SnapshotPricer(provider: FixedPrices(quote: quote)).snapshot(pricing: snapshot)
        }
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
