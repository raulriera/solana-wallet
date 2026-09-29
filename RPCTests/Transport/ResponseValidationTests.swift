import Foundation
import Testing
@testable import RPC

/// Verifies shared response validation through the real provider client.
struct ResponseValidationTests {
    /// Verifies unattributed provider rejections preserve their code and redact credentials.
    @Test("server errors with a null identifier retain their sanitized cause without retrying")
    func unattributedServerErrorsPreserveTheirCause() async {
        let transport = StubTransport { request in
            let (_, response) = try reply(to: request, payload: #""result":12345"#)
            return (Data(#"{"jsonrpc":"2.0","id":null,"error":{"code":-32601,"message":"Method not found for fixture-key"}}"#.utf8), response)
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.server(code: -32601, message: "Method not found for [redacted]")) {
            try await rpc.send(GetPriorityFeeEstimate(for: .accounts(["11111111111111111111111111111111"])))
        }
        #expect(await transport.requests.count == 1)
    }

    /// Verifies null identifiers cannot yield success and another request's error is rejected.
    /// - Parameter payload: A success without correlation or an error with the wrong identifier.
    @Test("uncorrelated results and mismatched server errors are rejected", arguments: [
        #""id":null,"result":12345"#,
        #""id":"another-request","error":{"code":-32601,"message":"Method not found"}"#,
    ])
    func uncorrelatedResponsesAreRejected(payload: String) async {
        let transport = StubTransport { request in
            let (_, response) = try reply(to: request, payload: #""result":12345"#)
            return (Data(#"{"jsonrpc":"2.0",\#(payload)}"#.utf8), response)
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.invalidResponse(.mismatchedID)) {
            try await rpc.send(GetBlockHeight())
        }
    }

    /// Verifies null-ID error support does not permit missing or wrongly typed identifiers.
    /// - Parameter identifier: An absent identifier or one with an incompatible JSON type.
    @Test("server errors still require a correctly typed identifier field", arguments: ["", #""id":1,"#, #""id":true,"#])
    func malformedErrorIdentifiersAreRejected(identifier: String) async {
        let transport = StubTransport { request in
            let (_, response) = try reply(to: request, payload: #""result":12345"#)
            return (Data(#"{"jsonrpc":"2.0",\#(identifier)"error":{"code":-32601,"message":"Method not found"}}"#.utf8), response)
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.decoding) { try await rpc.send(GetBlockHeight()) }
    }

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
