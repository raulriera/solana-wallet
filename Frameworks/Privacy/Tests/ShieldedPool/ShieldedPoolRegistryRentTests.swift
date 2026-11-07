import Foundation
@testable import Privacy
@testable import RPC
import Testing

struct ShieldedPoolRegistryRentTests {
    @Test
    func `Rent is read for a record's length`() async throws {
        let record = try #require(try RegistryVectors.load().records.first)
        let transport = StubTransport { request in try reply(to: request, payload: #""result":1586880"#) }

        let rent = try await ShieldedPool.registryRecordRent(using: SolanaRPC(network: .devnet, transport: transport))

        let requests = try await transport.requests.map(requestBody)
        let parameters = try #require(requests.first?["params"] as? [Any])
        #expect(rent == 1_586_880)
        #expect(requests.map { $0["method"] as? String } == ["getMinimumBalanceForRentExemption"])
        #expect(parameters.first as? Int == (try fixtureBytes(record.data)).count)
        #expect((parameters.last as? [String: Any])?["commitment"] as? String == "finalized")
    }
}
