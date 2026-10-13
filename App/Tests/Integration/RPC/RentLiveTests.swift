import RPC
import Testing

/// Verifies real mainnet rejection of rent queries.
@Suite(.tags(.network))
struct RentLiveTests {
    /// Verifies an impossible allocation is surfaced as the node's error, never a zero deposit.
    @Test(.timeLimit(.minutes(1)))
    func `Mainnet rejects rent queries for an impossible allocation`() async throws {
        let rpc = Solana(network: .mainnet)

        await #expect {
            try await rpc.send(GetMinimumBalanceForRentExemption(dataLength: .max))
        } throws: { error in
            guard case RPCError.server(code: -32600, message: _) = error else { return false }
            return true
        }
    }
}
