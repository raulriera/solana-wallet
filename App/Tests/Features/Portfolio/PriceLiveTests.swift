import Foundation
import RPC
import Testing

/// Verifies live market prices through the public provider-neutral contract.
struct PriceLiveTests {
    /// Fetches two mainnet market quotes without querying wallets or submitting transactions.
    ///
    /// Jupiter supplies mainnet market data; this test makes no devnet valuation claim.
    /// - Throws: A price-provider or test prerequisite error.
    @Test(.timeLimit(.minutes(1)))
    func `Live price provider returns normalized SOL and USDC quotes`() async throws {
        let source: any PriceProviding = Jupiter(apiKey: ProcessInfo.processInfo.environment["JUPITER_API_KEY"])
        let mints = ["So11111111111111111111111111111111111111112",
                     "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"]
        let quotes = try await source.prices(for: mints)

        #expect(source.network == .mainnet)
        for mint in mints {
            let quote = try #require(quotes[mint])
            #expect(quote.pricePerUnit > 0)
            #expect(quote.currency == "USD")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        print("Live price quotes:\n\(String(decoding: try encoder.encode(quotes), as: UTF8.self))")
    }
}
