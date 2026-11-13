import CryptoKit
import Foundation
import Synchronization
import Testing
@testable import RPC

struct AttestedProverKeyTests {
    typealias Responder = @Sendable (URLRequest) async throws -> (Data, URLResponse)?

    @Test
    func `An attestation gets the prover's attestation path with a lowercase hex nonce and no key`() async throws {
        let (key, transport, recorded) = try Self.attestedKey()

        #expect(Array(try await key.key().rawRepresentation) == (try recorded.hpkePublicKey))
        let request = try #require(await transport.requests.first)
        let url = try #require(request.url)
        #expect(request.httpMethod == "GET")
        #expect(url.path() == "/attestation")
        #expect(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [
                URLQueryItem(name: "nonce", value: recorded.nonce)
            ]
        )
        #expect(request.httpBody == nil)
        #expect((request.allHTTPHeaderFields ?? [:]).isEmpty)
    }

    @Test(arguments: [(0, 1), (599, 1), (600, 2), (900, 2), (-1, 2)] as [(TimeInterval, Int)])
    func `A key is reused from its attestation's start until the policy's maximum age`(
        elapsed: TimeInterval,
        requests: Int
    ) async throws {
        let clock = Mutex<TimeInterval>(0)
        let (key, transport, recorded) = try Self.attestedKey(elapsed: { clock.withLock { $0 } })
        _ = try await key.key()
        clock.withLock { $0 = elapsed }

        let reused = try await key.key()

        #expect(Array(reused.rawRepresentation) == (try recorded.hpkePublicKey))
        #expect(await transport.requests.count == requests)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Concurrent callers share one attestation`() async throws {
        let gate = Suspension()
        let (key, transport, recorded) = try Self.attestedKey(respond: { _ in
            await gate.suspend()
            return nil
        })

        async let first = key.key()
        await gate.waitUntilStarted()
        async let second = key.key()
        gate.resume()
        let keys = try await [first, second]

        let expected = try recorded.hpkePublicKey
        #expect(keys.map { Array($0.rawRepresentation) } == [expected, expected])
        #expect(await transport.requests.count == 1)
    }

    @Test
    func `A refused attestation surfaces its HTTP error and isn't kept`() async throws {
        let attempts = Mutex(0)
        let (key, transport, recorded) = try Self.attestedKey(respond: { request in
            let attempt = attempts.withLock { count in
                count += 1
                return count
            }
            guard attempt == 1 else { return nil }
            return try httpReply(to: request, body: #"{"code":"attestation_unavailable"}"#, status: 503)
        })

        await #expect(throws: RPCError.http(statusCode: 503, retryAfter: nil)) { try await key.key() }
        let retried = try await key.key()

        #expect(Array(retried.rawRepresentation) == (try recorded.hpkePublicKey))
        #expect(await transport.requests.count == 2)
    }

    @Test
    func `An attestation longer than 64 KiB is refused`() async throws {
        let (key, _, _) = try Self.attestedKey(respond: { request in
            try httpReply(to: request, body: String(repeating: " ", count: 65_537))
        })

        await #expect(throws: RPCError.invalidResponse(.oversized)) { try await key.key() }
    }

    static func attestedKey(
        on network: Network = .devnet,
        elapsed: @escaping @Sendable () -> TimeInterval = { 0 },
        respond: @escaping Responder = { _ in nil }
    ) throws -> (key: AttestedProverKey, transport: StubTransport, recorded: RecordedNitroAttestation) {
        let file = network == .devnet ? "RecordedDevnetNitroAttestation" : "RecordedMainnetNitroAttestation"
        let recorded = try RecordedNitroAttestation.load(named: file)
        let body = try recorded.responseBody()
        let nonce = try fixtureBytes(recorded.nonce)
        let transport = StubTransport { request in
            try await respond(request) ?? httpReply(to: request, body: body)
        }
        let zolana = Zolana(
            network: network,
            endpoint: Zolana.stubEndpoint,
            redactor: SecretRedactor(secrets: []),
            transport: transport,
            nonce: { nonce },
            now: { recorded.capturedDate.addingTimeInterval(elapsed()) }
        )
        return (zolana.attestedKey, transport, recorded)
    }
}
