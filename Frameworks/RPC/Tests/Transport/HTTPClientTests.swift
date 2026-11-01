import Foundation
import Testing
@testable import RPC

struct HTTPClientTests {
    private struct Reading: Decodable, Equatable, Sendable {
        let value: Int
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
            decoding: Reading.self
        )

        #expect(reading == Reading(value: 7))
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://prover.example.com/v1/tee/v1/attestation?region=1&nonce=0a1b")
        #expect(request.httpBody == nil)
    }
}
