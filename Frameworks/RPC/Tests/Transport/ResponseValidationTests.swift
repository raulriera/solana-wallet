import Foundation
import Testing
@testable import RPC

struct ResponseValidationTests {
    @Test
    func `Server errors with a null identifier retain their sanitized cause without retrying`() async {
        let transport = StubTransport { request in
            let (_, response) = try reply(to: request, payload: #""result":12345"#)
            return (Data(#"{"jsonrpc":"2.0","id":null,"error":{"code":-32601,"message":"Method not found for fixture-key"}}"#.utf8), response)
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.server(code: -32601, message: "Method not found for [redacted]")) {
            try await rpc.send(GetBlockHeight())
        }
        #expect(await transport.requests.count == 1)
    }

    @Test(arguments: [
        #""id":null,"result":12345"#,
        #""id":"another-request","error":{"code":-32601,"message":"Method not found"}"#,
    ])
    func `Uncorrelated results and mismatched server errors are rejected`(payload: String) async {
        let transport = StubTransport { request in
            let (_, response) = try reply(to: request, payload: #""result":12345"#)
            return (Data(#"{"jsonrpc":"2.0",\#(payload)}"#.utf8), response)
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.invalidResponse(.mismatchedID)) {
            try await rpc.send(GetBlockHeight())
        }
    }

    @Test(arguments: ["", #""id":1,"#, #""id":true,"#])
    func `Server errors still require a correctly typed identifier field`(identifier: String) async {
        let transport = StubTransport { request in
            let (_, response) = try reply(to: request, payload: #""result":12345"#)
            return (Data(#"{"jsonrpc":"2.0",\#(identifier)"error":{"code":-32601,"message":"Method not found"}}"#.utf8), response)
        }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)

        await #expect(throws: RPCError.decoding) { try await rpc.send(GetBlockHeight()) }
    }

    @Test(arguments: [
        (#""jsonrpc":"1.0","result":12345"#, RPCError.InvalidResponse.unsupportedVersion),
        (#""jsonrpc":"2.0","result":12345,"error":{"code":-32603,"message":"failed"}"#, .invalidEnvelope),
        (#""jsonrpc":"2.0""#, .invalidEnvelope),
    ])
    func `Responses with invalid JSON-RPC envelopes are rejected`(payload: String, reason: RPCError.InvalidResponse) async {
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
