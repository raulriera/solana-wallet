import Foundation
import Testing
@testable import RPC

/// Verifies supplied-blockhash validity through the real RPC client and JSON codec.
struct BlockhashValidityTests {
    /// Verifies valid and expired hashes retain their boolean result and ledger context.
    ///
    /// - Parameter valid: The server's recent-blockhash observation.
    @Test(arguments: [true, false])
    func `Blockhash checks return validity and the evaluated slot`(_ valid: Bool) async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":402},"value":\#(valid)}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)
        let hash = "11111111111111111111111111111111"

        let result = try await rpc.send(IsBlockhashValid(blockhash: hash, minContextSlot: 400))

        #expect(result.value == valid)
        #expect(result.context.slot == 402)
        let body = try requestBody(#require(await transport.requests.first))
        #expect(body["method"] as? String == "isBlockhashValid")
        let params = try #require(body["params"] as? [Any])
        #expect(params.count == 2)
        #expect(params.first as? String == hash)
        let configuration = try #require(params.last as? [String: Any])
        #expect(configuration["minContextSlot"] as? UInt64 == 400)
    }

    /// Verifies absent or incorrectly typed validity can never be interpreted as approval.
    ///
    /// - Parameter value: An absent, null, or nonboolean JSON field.
    @Test(arguments: ["", ",\"value\":null", ",\"value\":1"])
    func `Malformed blockhash validity cannot be treated as valid`(_ value: String) async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":402}\#(value)}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.decoding) {
            try await rpc.send(IsBlockhashValid(blockhash: "11111111111111111111111111111111"))
        }
    }
}
