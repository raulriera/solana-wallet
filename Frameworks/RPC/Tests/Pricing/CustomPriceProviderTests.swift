import Foundation
import Testing
@testable import RPC

struct CustomPriceProviderTests {
    private static let endpoint = URL(string: "https://prices.example.com/v1/quotes?key=fixture-key")!

    @Test(arguments: ["http://prices.example.com", "https://", "ftp://prices.example.com", "prices.example.com"])
    func `Only HTTPS endpoints with a host make a provider`(_ text: String) throws {
        let transport = StubTransport { try httpReply(to: $0, body: "{}") }
        #expect(CustomPriceProvider(endpoint: try #require(URL(string: text)), transport: transport) == nil)
    }

    @Test
    func `Prices decode the server's quotes exactly, leave missing mints unpriced, and ignore a bad change`() async throws {
        let transport = StubTransport { request in
            try httpReply(to: request, body: #"""
                {"mint-a":{"pricePerUnit":0.0000030558913710262106,"currency":"USD","dayChange":0.0129},
                 "mint-b":{"pricePerUnit":0,"currency":"EUR"},"mint-c":{"pricePerUnit":2,"currency":"USD","dayChange":"soon"}}
                """#)
        }
        let source = try #require(CustomPriceProvider(endpoint: Self.endpoint, transport: transport))

        let quotes = try await source.prices(for: ["mint-a", "mint-b", "mint-c", "unpriced"])

        #expect(source.network == .mainnet)
        #expect(quotes == [
            "mint-a": Quote(pricePerUnit: try #require(Decimal(string: "0.0000030558913710262106")), currency: "USD",
                            dayChange: Decimal(string: "0.0129")),
            "mint-b": Quote(pricePerUnit: 0, currency: "EUR", dayChange: nil),
            "mint-c": Quote(pricePerUnit: 2, currency: "USD", dayChange: nil),
        ])
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.url?.host() == "prices.example.com")
        #expect(request.url?.path() == "/v1/quotes")
        #expect(try requestedMints(request, query: "key") == ["fixture-key"])
        #expect(try requestedMints(request, query: "mints") == ["mint-a", "mint-b", "mint-c", "unpriced"])
    }

    @Test(.timeLimit(.minutes(1)))
    func `Batches of fifty mints wait three seconds apart`() async throws {
        let clock = ManualClock()
        let startedAt = clock.now
        let transport = StubTransport { try httpReply(to: $0, body: "{}") }
        let source = try #require(CustomPriceProvider(endpoint: Self.endpoint, transport: transport, clock: clock))
        let mints = (0..<51).map { "mint-\($0)" }
        async let operation = source.prices(for: mints)
        var waits = clock.waits.makeAsyncIterator()

        let deadline = try #require(await clock.nextDeadline(&waits))
        #expect(deadline == startedAt.advanced(by: .seconds(3)))
        #expect(await transport.requests.count == 1)
        clock.advance(to: deadline)
        _ = try await operation

        #expect(try await transport.requests.map { try requestedMints($0, query: "mints").count } == [50, 1])
    }

    @Test(arguments: [
        #"{"mint":{"pricePerUnit":-1,"currency":"USD"}}"#,
        #"{"mint":{"pricePerUnit":1,"currency":"DOLLARS"}}"#,
        #"{"mint":{"pricePerUnit":1,"currency":""}}"#,
        #"{"mint":{"pricePerUnit":1}}"#,
        #"{"mint":{"pricePerUnit":"1","currency":"USD"}}"#,
        #"{"mint":null}"#,
        #"[]"#,
    ])
    func `Invalid answers fail without inventing a quote`(_ body: String) async throws {
        let transport = StubTransport { try httpReply(to: $0, body: body) }
        let source = try #require(CustomPriceProvider(endpoint: Self.endpoint, transport: transport))
        await #expect(throws: RPCError.decoding) { try await source.prices(for: ["mint"]) }
    }

    @Test
    func `Answers longer than one mebibyte fail`() async throws {
        let transport = StubTransport { try httpReply(to: $0, body: "{" + String(repeating: " ", count: 1_048_576) + "}") }
        let source = try #require(CustomPriceProvider(endpoint: Self.endpoint, transport: transport))
        await #expect(throws: RPCError.invalidResponse(.oversized)) { try await source.prices(for: ["mint"]) }
    }

    @Test
    func `Rate limits surface without retries and keep the endpoint out of diagnostics`() async throws {
        let transport = StubTransport { request in
            try httpReply(to: request, body: "{}", status: 429, headers: ["Retry-After": "5 fixture-key"])
        }
        let source = try #require(CustomPriceProvider(endpoint: Self.endpoint, transport: transport))

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: "5 [redacted]")) {
            try await source.prices(for: ["mint"])
        }

        #expect(await transport.requests.count == 1)
        #expect(!String(describing: source).contains("fixture-key"))
        #expect(!String(reflecting: source).contains("fixture-key"))
    }
}
