import RPC
import Testing

@Suite(.tags(.network))
struct RentLiveTests {
    @Test(.timeLimit(.minutes(1)))
    func `Mainnet rejects rent queries for an impossible allocation`() async throws {
        let rpc = SolanaRPC(network: .mainnet)

        let error = try await #require(throws: RPCError.self) {
            try await rpc.send(GetMinimumBalanceForRentExemption(dataLength: .max))
        }
        #expect(error.serverCode == -32600, "Received \(error)")
    }
}
