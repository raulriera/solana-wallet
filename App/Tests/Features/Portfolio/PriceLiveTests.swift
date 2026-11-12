import Foundation
import RPC
import Testing

@Suite(.tags(.network))
struct PriceLiveTests {
    @Test(.timeLimit(.minutes(1)))
    func `Live price provider returns normalized SOL and USDC quotes`() async throws {
        let source: any PriceProviding = JupiterPriceProvider()
        let mints = ["So11111111111111111111111111111111111111112",
                     "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"]
        let quotes = try await source.prices(for: mints)

        #expect(source.network == .mainnet)
        for mint in mints {
            let quote = try #require(quotes[mint])
            #expect(quote.pricePerUnit > 0)
            #expect(quote.currency == "USD")
            #expect(quote.dayChange != nil)
        }
    }
}
