import RPC
import Testing

@Suite(.tags(.network))
struct RentLiveTests {
    @Test(.timeLimit(.minutes(1)))
    func `Mainnet rejects rent queries for an impossible allocation`() async throws {
        let rpc = SolanaRPC(network: .mainnet)

        await #expect {
            try await rpc.send(GetMinimumBalanceForRentExemption(dataLength: .max))
        } throws: { error in
            guard case RPCError.server(code: -32600, message: _) = error else { return false }
            return true
        }
    }
}
