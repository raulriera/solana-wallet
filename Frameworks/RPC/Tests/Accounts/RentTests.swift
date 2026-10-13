import Foundation
import RPC
import Testing

/// Verifies the rent request's wire contract and real mainnet rejection behavior.
struct RentTests {
    /// Verifies rent is queried for the specified size and explicit commitment only.
    @Test
    func `Rent queries encode the allocation size and finalized commitment`() throws {
        let request = GetMinimumBalanceForRentExemption(dataLength: 182)
        let parameters = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [Any])

        #expect(GetMinimumBalanceForRentExemption.method == "getMinimumBalanceForRentExemption")
        #expect(parameters.count == 2)
        #expect(parameters.first as? UInt64 == 182)
        #expect(parameters.last as? [String: String] == ["commitment": "finalized"])
    }

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
