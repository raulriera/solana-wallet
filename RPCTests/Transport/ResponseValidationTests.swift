import Foundation
import Testing
@testable import RPC

/// Verifies shared response validation through the real provider client.
struct ResponseValidationTests {
    /// Verifies a matching identifier cannot make an invalid protocol envelope acceptable.
    /// - Parameters:
    ///   - payload: A wrong version, conflicting outcomes, or missing outcome.
    ///   - reason: The specific validation failure exposed to the consumer.
    @Test("responses with invalid JSON-RPC envelopes are rejected", arguments: [
        (#""jsonrpc":"1.0","result":12345"#, RPCError.InvalidResponse.unsupportedVersion),
        (#""jsonrpc":"2.0","result":12345,"error":{"code":-32603,"message":"failed"}"#, .invalidEnvelope),
        (#""jsonrpc":"2.0""#, .invalidEnvelope),
    ])
    func invalidEnvelopesAreRejected(payload: String, reason: RPCError.InvalidResponse) async {
        let transport = StubTransport { request in
            let id = try #require(requestBody(request)["id"] as? String)
            let (_, response) = try reply(to: request, payload: #""result":12345"#)
            return (Data(#"{"id":"\#(id)",\#(payload)}"#.utf8), response)
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.invalidResponse(reason)) {
            try await rpc.send(GetBlockHeight())
        }
    }
}
