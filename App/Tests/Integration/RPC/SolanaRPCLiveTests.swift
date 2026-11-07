import Foundation
import RPC
import Testing

@Suite(.tags(.network), .timeLimit(.minutes(1)))
struct SolanaRPCLiveTests {
    @Test
    func `A custom endpoint reads accounts and acknowledges subscriptions`() async throws {
        let rpc = try #require(SolanaRPC(endpoint: URL(string: "https://api.mainnet.solana.com")!, network: .mainnet))
        let nativeMint = "So11111111111111111111111111111111111111112"

        let response = try await rpc.send(GetMultipleAccounts(addresses: [nativeMint]))
        _ = try await rpc.changedSlots(for: [nativeMint])

        #expect(response.value.first??.owner == "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
    }
}
