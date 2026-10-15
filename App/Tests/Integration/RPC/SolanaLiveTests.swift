import Foundation
import RPC
import Testing

/// Verifies a custom endpoint against public mainnet RPC, given as a URL.
@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct SolanaLiveTests {
    /// Reads the native mint and watches it through the same URL, without reading wallets or submitting transactions.
    @Test
    func `A custom endpoint reads accounts and acknowledges subscriptions`() async throws {
        let rpc = try #require(Solana(endpoint: URL(string: "https://api.mainnet.solana.com")!, network: .mainnet))
        let nativeMint = "So11111111111111111111111111111111111111112"

        let response = try await rpc.send(GetMultipleAccounts(addresses: [nativeMint]))
        // Returning means the subscription was acknowledged; dropping the stream closes its connection.
        _ = try await rpc.changedSlots(for: [nativeMint])

        #expect(response.value.first??.owner == "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
    }
}
