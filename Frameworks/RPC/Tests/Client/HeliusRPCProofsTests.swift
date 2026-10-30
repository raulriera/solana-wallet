import Foundation
import Testing
@testable import RPC

struct HeliusRPCProofsTests {
    private typealias Fixture = ProofFixtures

    @Test(arguments: [(Network.mainnet, "mainnet.helius-rpc.com"), (.devnet, "devnet.helius-rpc.com")])
    func `Proofs post to the complete route`(network: Network, host: String) async throws {
        let transport = StubTransport { request in
            let url = try #require(request.url)
            return (Data(Fixture.response().utf8), try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                                              headerFields: nil)))
        }
        let provider: any ProofProviding = HeliusRPC(apiKey: "fixture-key", network: network, transport: transport)
        let request = try Fixture.request()

        let proof = try await provider.proveTransfer(request)

        #expect(proof.provingKeyDigest == Array(repeating: 0x7e, count: 32))
        let sent = try #require(await transport.requests.first)
        #expect(sent.url?.absoluteString == "https://\(host)/v1/zolana/prove?api-key=fixture-key")
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "X-Sync") == "true")
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try requestBody(sent)["publicInputHash"] as? String == "0x99")
    }

    @Test(arguments: [400, 401, 408, 429])
    func `Prover refusals surface as HTTP errors without the key`(status: Int) async throws {
        let transport = StubTransport { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                                        headerFields: ["Retry-After": "fixture-key"]))
            return (Data(#"{"code":"proof_timeout","message":"fixture-key"}"#.utf8), response)
        }
        let provider = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)
        let request = try Fixture.request()

        await #expect(throws: RPCError.http(statusCode: status, retryAfter: "[redacted]")) {
            try await provider.proveTransfer(request)
        }
    }

    @Test
    func `A body without a digest fails to decode`() async throws {
        let transport = StubTransport { request in
            let url = try #require(request.url)
            return (Data(Fixture.response(digest: nil).utf8),
                    try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
        }
        let provider = HeliusRPC(apiKey: "fixture-key", network: .devnet, transport: transport)
        let request = try Fixture.request()

        await #expect(throws: RPCError.decoding) { try await provider.proveTransfer(request) }
    }
}
