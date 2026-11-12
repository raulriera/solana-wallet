import Foundation
import Testing
@testable import RPC

struct EpochInfoTests {
    @Test
    func `Epoch reads return the epoch, observation slot, and block height`() async throws {
        let (rpc, transport) = Self.rpc(replyingAt: 43200001)
        let result = try await rpc.send(GetEpochInfo(minContextSlot: 43200000))
        #expect(result.epoch == 100)
        #expect(result.absoluteSlot == 43200001)
        #expect(result.blockHeight == 41000017)
        let body = try requestBody(#require(await transport.requests.first))
        #expect(body["method"] as? String == "getEpochInfo")
        let params = try #require(body["params"] as? [[String: Any]])
        #expect(params.first?["minContextSlot"] as? UInt64 == 43200000)
    }

    @Test
    func `Epoch reads reject a response from before the minimum slot`() async {
        let (rpc, _) = Self.rpc(replyingAt: 43199999)

        await #expect(throws: RPCError.invalidResponse(.staleContext)) {
            try await rpc.send(GetEpochInfo(minContextSlot: 43200000))
        }
    }

    private static func rpc(replyingAt absoluteSlot: UInt64) -> (HeliusRPC, StubTransport) {
        let transport = StubTransport { request in
            try reply(to: request,
                      payload: #""result":{"epoch":100,"absoluteSlot":\#(absoluteSlot),"blockHeight":41000017}"#)
        }
        return (HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport), transport)
    }
}
