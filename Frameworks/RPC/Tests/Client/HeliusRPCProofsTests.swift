import Foundation
import Testing
@testable import RPC

/// Exercises transfer proofs through the real Helius client and recorded prover responses.
struct HeliusRPCProofsTests {
    private typealias Fixture = ProofFixtures

    /// Verifies the request posts the body to the gateway's complete route with the key and `X-Sync`.
    ///
    /// - Parameters:
    ///   - network: The selected network.
    ///   - host: The Helius host that serves it.
    /// - Throws: An RPC, encoding, or parsing error, or a failed test prerequisite.
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
        // TransferProofBodyTests pins the body's fields.
        #expect(try requestBody(sent)["publicInputHash"] as? String == "0x99")
    }

    /// Verifies refusals surface as HTTP errors whatever their body, with the key redacted from the retry delay.
    ///
    /// - Parameter status: A refusal: a witness that the circuit rejects, a missing key, a proof timeout, or a busy
    ///   prover.
    /// - Throws: A failed test prerequisite.
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

    /// Verifies a successful body that isn't a proof, such as one without its digest, fails with a decoding error.
    ///
    /// - Throws: A failed test prerequisite.
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
