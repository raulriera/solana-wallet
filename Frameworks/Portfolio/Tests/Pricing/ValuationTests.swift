import Foundation
import RPC
import Testing
import Transactions
@testable import Portfolio

struct ValuationTests {
    @Test(arguments: [
        (Amount(units: .max, decimals: 6), Decimal(string: "0.1")!, Decimal(string: "1844674407370.9551615")),
        (Amount(units: 1, decimals: 9), Decimal(string: "123.456789")!, Decimal(string: "0.000000123456789")),
        (Amount(units: 0, decimals: .max), Decimal(10), Decimal(0)),
        (Amount(units: 1, decimals: .max), Decimal(0), Decimal(0)),
        (Amount(units: 1, decimals: .max), Decimal(10), nil),
        (Amount(units: .max, decimals: 0), Decimal.greatestFiniteMagnitude, nil),
    ])
    func `Valuation preserves decimal precision and never invents unrepresentable totals`(amount: Amount, price: Decimal, total: Decimal?) async throws {
        let quote = Quote(pricePerUnit: price, currency: "CAD", dayChange: nil)
        let snapshot = Snapshot(owner: "wallet", network: .devnet, holdings: [
            Holding(id: .asset("mint"), amount: amount, name: "Token", symbol: "TOK", imageURL: nil, valuation: nil),
        ])
        let result = try await valued(snapshot, with: FixedPrices(quote: quote))
        let valuation = try #require(result.holdings.first?.valuation)
        #expect(valuation.pricePerUnit == price)
        #expect(valuation.total == total)
        #expect(valuation.currency == "CAD")
    }

    @Test(arguments: [
        Quote(pricePerUnit: -1, currency: "USD", dayChange: nil),
        Quote(pricePerUnit: .nan, currency: "USD", dayChange: nil),
        Quote(pricePerUnit: 1, currency: " ", dayChange: nil),
    ])
    func `Invalid independent quotes fail valuation`(quote: Quote) async {
        let snapshot = Snapshot(owner: "wallet", network: .devnet, holdings: [
            Holding(id: .asset("mint"), amount: Amount(units: 1, decimals: 0), name: nil, symbol: nil, imageURL: nil,
                    valuation: nil),
        ])
        await #expect(throws: PriceError.invalidQuote) {
            try await valued(snapshot, with: FixedPrices(quote: quote))
        }
    }

    @Test
    func `A holding without a balance has no valuation`() async throws {
        let quote = Quote(pricePerUnit: 1, currency: "USD", dayChange: Decimal(string: "0.01"))
        let snapshot = Snapshot(owner: "wallet", network: .devnet, holdings: [
            Holding(id: .asset("mint"), amount: nil, otherOwner: try Address(otherWallet), name: nil, symbol: nil,
                    imageURL: nil, valuation: Valuation(pricePerUnit: 1, total: nil, currency: "USD")),
        ])

        let result = try await valued(snapshot, with: FixedPrices(quote: quote))

        #expect(result.holdings.first?.valuation == nil)
    }

    @Test(arguments: [Decimal(string: "0.0129"), nil])
    func `Valuations keep the quote's 24-hour change`(change: Decimal?) async throws {
        let valuation = try await pricedValuation(dayChange: change)
        #expect(valuation.total == 2)
        #expect(valuation.dayChange == change)
    }

    @Test
    func `A 24-hour change that isn't a number stays unknown`() async throws {
        let valuation = try await pricedValuation(dayChange: .nan)
        #expect(valuation.total == 2)
        #expect(valuation.dayChange == nil)
    }

    @Test
    func `Saved valuations without a 24-hour change still load`() throws {
        let saved = Data(#"{"pricePerUnit":2,"total":4,"currency":"USD"}"#.utf8)
        let valuation = try JSONDecoder().decode(Valuation.self, from: saved)
        #expect(valuation.total == 4)
        #expect(valuation.dayChange == nil)
    }

    private func pricedValuation(dayChange: Decimal?) async throws -> Valuation {
        let quote = Quote(pricePerUnit: 2, currency: "USD", dayChange: dayChange)
        let snapshot = Snapshot(owner: "wallet", network: .devnet, holdings: [
            Holding(id: .asset("mint"), amount: Amount(units: 1, decimals: 0), name: nil, symbol: nil, imageURL: nil,
                    valuation: nil),
        ])
        let result = try await valued(snapshot, with: FixedPrices(quote: quote))
        return try #require(result.holdings.first?.valuation)
    }

    private func valued(_ snapshot: Snapshot, with provider: any PriceProviding) async throws -> Snapshot {
        let pricer = SnapshotPricer(provider: provider)
        return try pricer.snapshot(pricing: snapshot, with: await pricer.quotes(for: snapshot.holdings.map(\.id)))
    }
}

private struct FixedPrices: PriceProviding {
    let network: Network = .devnet
    let quote: Quote

    func prices(for mints: [String]) async throws -> [String: Quote] {
        Dictionary(mints.map { ($0, quote) }) { first, _ in first }
    }
}
