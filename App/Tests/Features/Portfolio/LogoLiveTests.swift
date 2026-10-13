import Foundation
import RPC
import Testing
@testable import widgets

/// Verifies live logo lookups through the provider-neutral contract with real Helius responses.
@Suite(.tags(.network))
struct LogoLiveTests {
    /// Loads a mainnet logo after an old CDN error for it was cached, without reading balances or submitting transactions.
    ///
    /// - Throws: An RPC or test prerequisite error.
    @Test(.timeLimit(.minutes(1)))
    func `An expired cached error doesn't hide a live logo`() async throws {
        let usdc = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
        let provider: any LogoProviding = HeliusRPC(apiKey: try LiveClients.heliusAPIKey(), network: .mainnet)
        let logo = try #require(try await provider.logos(for: [usdc])[usdc])
        // The CDN answered 404 days ago, with its usual four-hour cache time.
        let request = URLRequest(url: logo)
        let notFound = try #require(HTTPURLResponse(url: logo, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: [
            "Cache-Control": "public, max-age=14400", "Date": "Mon, 05 Oct 2026 00:00:00 GMT"]))
        URLCache.shared.storeCachedResponse(CachedURLResponse(response: notFound, data: Data()), for: request)
        defer { URLCache.shared.removeCachedResponse(for: request) }

        #expect(await ArtworkColors().color(for: logo) != nil)
    }

    /// Looks up two mainnet tokens and a wallet address without reading balances or submitting transactions.
    ///
    /// - Throws: An RPC or test prerequisite error.
    @Test(.timeLimit(.minutes(1)))
    func `Live logos come only from Helius's CDN`() async throws {
        let usdc = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
        let bonk = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
        let provider: any LogoProviding = HeliusRPC(apiKey: try LiveClients.heliusAPIKey(), network: .mainnet)

        let logos = try await provider.logos(for: [usdc, bonk, PublicWallet.address])

        #expect(Set(logos.keys) == [usdc, bonk])
        #expect(logos.values.allSatisfy { $0.scheme == "https" && $0.host() == "cdn.helius-rpc.com" })
    }
}
