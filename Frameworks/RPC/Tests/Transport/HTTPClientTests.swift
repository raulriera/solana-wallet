import Foundation
import Testing
@testable import RPC

struct HTTPClientTests {
    private struct Reading: Codable, Equatable, Sendable {
        let value: Int
    }

    private static let answerBody = Data(#"{"proof":"ok"}"#.utf8)

    private let prover: TestProver

    init() throws {
        prover = try TestProver(vectors: EncryptedProverVectors.load())
    }

    @Test
    func `A GET adds the path and query to the endpoint's and decodes the body without sending one`() async throws {
        let transport = StubTransport { try httpReply(to: $0, body: #"{"value":7}"#) }
        let client = HTTPClient(
            endpoint: try #require(URL(string: "https://prover.example.com/v1?region=1")),
            transport: transport,
            redactor: SecretRedactor(secrets: [])
        )

        let reading = try await client.get(
            at: "tee/v1/attestation",
            query: [URLQueryItem(name: "nonce", value: "0a1b")],
            maximumLength: 64,
            decoding: Reading.self
        )

        #expect(reading == Reading(value: 7))
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://prover.example.com/v1/tee/v1/attestation?region=1&nonce=0a1b")
        #expect(request.httpBody == nil)
    }

    @Test
    func `A sealed POST reaches the prover below the endpoint with the caller's headers and opens its answer`()
        async throws {
        let transport = answering(Self.answerBody)

        let answer = try await post(through: transport)

        #expect(answer == .init(status: 200, body: Self.answerBody))
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://prover.example.com/v1/zolana/prove/transfer_2_2/indexed")
        #expect(request.value(forHTTPHeaderField: "X-Sync") == "true")
        #expect(try prover.open(request).body == Data(#"{"value":7}"#.utf8))
    }

    @Test(arguments: [
        (429, ["Retry-After": "fixture-key"], #"{"code":"prover_busy"}"#,
         RPCError.http(statusCode: 429, retryAfter: "[redacted]")),
        (400, [:], #"{"code":"tee_decryption_failed"}"#, .invalidResponse(.staleProverKey)),
    ] as [(Int, [String: String], String, RPCError)])
    func `A sealed POST surfaces an unencrypted refusal by its status and code without secrets`(
        status: Int,
        headers: [String: String],
        body: String,
        error: RPCError
    ) async throws {
        let transport = StubTransport { try httpReply(to: $0, body: body, status: status, headers: headers) }

        await #expect(throws: error) { try await post(through: transport) }
    }

    @Test
    func `A sealed POST refuses an encrypted answer longer than the limit`() async throws {
        await #expect(throws: RPCError.invalidResponse(.oversized)) {
            try await post(through: answering(Data(count: 64)))
        }
    }

    private func answering(_ body: Data) -> StubTransport {
        StubTransport { [prover] request in try prover.open(request).answer(status: 200, body: body) }
    }

    private func post(through transport: StubTransport) async throws -> SealedProverRequest.Answer {
        let client = HTTPClient(
            endpoint: try #require(URL(string: "https://prover.example.com/v1/zolana")),
            transport: transport,
            redactor: SecretRedactor(secrets: ["fixture-key"])
        )
        return try await client.post(
            sealing: Reading(value: 7),
            at: "prove/transfer_2_2/indexed",
            headers: ["X-Sync": "true"],
            maximumLength: 64,
            to: prover.publicKey
        )
    }
}
