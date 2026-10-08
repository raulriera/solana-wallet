import Foundation
import RPC
import Testing

/// Verifies live logo lookups through the provider-neutral contract with real Helius responses.
struct LogoLiveTests {
    /// Looks up two mainnet tokens and a wallet address without reading balances or submitting transactions.
    ///
    /// - Throws: An RPC or test prerequisite error.
    @Test(.timeLimit(.minutes(1)))
    func `Live logos come only from Helius's CDN`() async throws {
        let usdc = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
        let bonk = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
        let provider: any LogoProviding = HeliusRPC(apiKey: try MainnetClients.heliusAPIKey(), network: .mainnet)

        let logos = try await provider.logos(for: [usdc, bonk, PublicWallet.address])

        #expect(Set(logos.keys) == [usdc, bonk])
        #expect(logos.values.allSatisfy { $0.scheme == "https" && $0.host() == "cdn.helius-rpc.com" })
    }
}
