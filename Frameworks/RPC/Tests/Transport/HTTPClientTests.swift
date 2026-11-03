import Foundation
import Synchronization
import Testing
@testable import RPC

struct HTTPClientTests {
    private struct Reading: Codable, Equatable, Sendable {
        let value: Int
    }

    @Test
    func `A GET adds the path and query below the endpoint and decodes the body without sending one`() async throws {
        let transport = StubTransport { try httpReply(to: $0, body: #"{"value":7}"#) }

        let reading = try await Self.client(transport).get(
            at: "attestation",
            query: [URLQueryItem(name: "nonce", value: "0a1b")],
            maximumLength: 64,
            decoding: Reading.self
        )

        #expect(reading == Reading(value: 7))
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://prover.example.com/attestation?nonce=0a1b")
        #expect(request.httpBody == nil)
    }

    @Test
    func `A POST sends its body and headers below the endpoint and decodes what the reader takes from any status`()
        async throws {
        let transport = StubTransport { try httpReply(to: $0, body: "wrapped", status: 503) }
        let read = Mutex<(body: Data, status: Int)?>(nil)

        let reading = try await Self.client(transport).post(
            Data("sealed".utf8),
            at: "prove/transfer_2_2/indexed",
            headers: ["Content-Type": "application/octet-stream", "X-Sync": "true"],
            maximumLength: 64,
            reading: { body, response in
                read.withLock { $0 = (body, response.statusCode) }
                return Data(#"{"value":9}"#.utf8)
            },
            decoding: Reading.self
        )

        #expect(reading == Reading(value: 9))
        #expect(read.withLock { $0?.body } == Data("wrapped".utf8))
        #expect(read.withLock { $0?.status } == 503)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://prover.example.com/prove/transfer_2_2/indexed")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        #expect(request.value(forHTTPHeaderField: "X-Sync") == "true")
        #expect(request.httpBody == Data("sealed".utf8))
    }

    @Test
    func `A POST surfaces the reader's error without secrets`() async throws {
        let transport = StubTransport { try httpReply(to: $0, body: "{}") }

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: "[redacted]")) {
            try await Self.post(through: transport) { _, _ in
                throw RPCError.http(statusCode: 429, retryAfter: "fixture-key")
            }
        }
    }

    @Test
    func `A POST refuses a response longer than the limit`() async throws {
        let transport = StubTransport { try httpReply(to: $0, body: String(repeating: "a", count: 65)) }

        await #expect(throws: RPCError.invalidResponse(.oversized)) {
            try await Self.post(through: transport) { body, _ in body }
        }
    }

    private static func client(_ transport: StubTransport) throws -> HTTPClient {
        HTTPClient(
            endpoint: try #require(URL(string: "https://prover.example.com")),
            transport: transport,
            redactor: SecretRedactor(secrets: ["fixture-key"])
        )
    }

    private static func post(
        through transport: StubTransport,
        reading read: @Sendable (Data, HTTPURLResponse) throws -> Data
    ) async throws -> Reading {
        try await client(transport).post(
            Data("sealed".utf8),
            at: "prove/transfer_2_2/indexed",
            headers: [:],
            maximumLength: 64,
            reading: read,
            decoding: Reading.self
        )
    }
}
