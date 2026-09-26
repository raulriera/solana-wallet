import Foundation
import RPC
import Portfolio
import Testing

/// Tests usable portfolio values through the framework's public API.
struct SnapshotTests {
    /// Verifies currency isolation and explicit incomplete valuation using public fixtures.
    @Test("portfolio values keep quote currencies separate and count unpriced holdings")
    func portfolioValuesKeepQuoteCurrenciesSeparateAndCountUnpricedHoldings() {
        let holdings = [
            Holding(id: .nativeSOL, amount: Amount(units: 1, decimals: 9), name: "Solana", symbol: "SOL", imageURL: nil,
                    valuation: Valuation(pricePerUnit: nil, total: Decimal(string: "2.5"), currency: "USD")),
            Holding(id: .asset("token-a"), amount: nil, name: nil, symbol: nil, imageURL: nil,
                    valuation: Valuation(pricePerUnit: nil, total: 4, currency: "USD")),
            Holding(id: .asset("token-b"), amount: nil, name: nil, symbol: nil, imageURL: nil,
                    valuation: Valuation(pricePerUnit: nil, total: 3, currency: "USDC")),
            Holding(id: .asset("token-c"), amount: nil, name: nil, symbol: nil, imageURL: nil, valuation: nil),
        ]

        let snapshot = Snapshot(owner: "wallet", network: .mainnet, holdings: holdings,
                                fetchedAt: Date(timeIntervalSince1970: 1), lastIndexedSlot: nil)

        #expect(snapshot.knownValuesByCurrency["USD"] == Decimal(string: "6.5"))
        #expect(snapshot.knownValuesByCurrency["USDC"] == 3)
        #expect(snapshot.unpricedHoldingCount == 1)
    }
}
