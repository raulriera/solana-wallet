import Foundation
@testable import Privacy
@testable import RPC
import Testing

/// Verifies the read of a user-registry record's rent through a real RPC client with local
/// responses.
struct ShieldedPoolRegistryRentTests {
    /// Verifies that the rent is one finalized `getMinimumBalanceForRentExemption` read of 134 bytes.
    @Test
    func `Rent is read for a record's 134 bytes`() async throws {
        let transport = StubTransport { request in try reply(to: request, payload: #""result":1823520"#) }

        let rent = try await ShieldedPool.registryRecordRent(using: Solana(network: .devnet, transport: transport))

        let requests = try await transport.requests.map(requestBody)
        let parameters = try #require(requests.first?["params"] as? [Any])
        #expect(rent == 1_823_520)
        #expect(requests.map { $0["method"] as? String } == ["getMinimumBalanceForRentExemption"])
        #expect(parameters.first as? Int == 134)
        #expect((parameters.last as? [String: Any])?["commitment"] as? String == "finalized")
    }
}
