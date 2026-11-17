import Foundation
import Testing
@testable import RPC

struct JupiterPriceProviderTests {
    @Test
    func `Quotes keep exact prices and fractional day changes and leave bad or missing values absent`() async throws {
        let transport = StubTransport { request in
            try httpReply(to: request, body: #"""
                {"mint-a":{"usdPrice":0.12345678901234567890123456789012,"blockId":9007199254740993,"decimals":9,
                           "priceChange24h":1.29},
                 "mint-b":{"usdPrice":0,"priceChange24h":-3.47},
                 "metadata-only":{"createdAt":"2025-01-01T00:00:00Z","liquidity":0.12,"decimals":6},
                 "null-price":{"usdPrice":null},"null-record":null,
                 "missing":{"usdPrice":4},"malformed":{"usdPrice":5,"priceChange24h":"soon"}}
                """#)
        }
        let source: any PriceProviding = JupiterPriceProvider(transport: transport)

        let quotes = try await source.prices(for: ["mint-a", "mint-b", "metadata-only", "null-price", "null-record",
                                                    "missing", "malformed", "unpriced"])

        #expect(quotes == [
            "mint-a": Quote(pricePerUnit: try #require(Decimal(string: "0.12345678901234567890123456789012")),
                            currency: "USD", dayChange: Decimal(string: "0.0129")),
            "mint-b": Quote(pricePerUnit: 0, currency: "USD", dayChange: Decimal(string: "-0.0347")),
            "missing": Quote(pricePerUnit: 4, currency: "USD", dayChange: nil),
            "malformed": Quote(pricePerUnit: 5, currency: "USD", dayChange: nil),
        ])
        let request = try #require(await transport.requests.first)
        let url = try #require(request.url)
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(url.host() == "api.jup.ag")
        #expect(url.path() == "/price/v3")
    }

    @Test(.timeLimit(.minutes(1)))
    func `Provider copies share the price budget across calls and batches`() async throws {
        let clock = ManualClock()
        let startedAt = clock.now
        let transport = StubTransport { try httpReply(to: $0, body: "{}") }
        let source = JupiterPriceProvider(transport: transport, clock: clock)
        _ = try await source.prices(for: ["initial"])
        let copy = source
        async let operation = copy.prices(for: (0..<51).map { "mint-\($0)" })
        var waits = clock.waits.makeAsyncIterator()

        let first = try #require(await clock.nextDeadline(&waits))
        #expect(first == startedAt.advanced(by: .seconds(3)))
        #expect(await transport.requests.count == 1)
        clock.advance(to: first)
        let second = try #require(await clock.nextDeadline(&waits))
        #expect(second == first.advanced(by: .seconds(3)))
        #expect(await transport.requests.count == 2)
        clock.advance(to: second)
        _ = try await operation

        #expect(try await transport.requests.map { try requestedMints($0, query: "ids").count } == [1, 50, 1])
    }

    @Test(.timeLimit(.minutes(1)))
    func `Rate limits fail the price lookup without retries or partial success`() async throws {
        let transport = StubTransport { request in
            if try requestedMints(request, query: "ids").first == "mint-50" {
                return try httpReply(to: request, body: "{}", status: 429,
                                      headers: ["Retry-After": "5"])
            }
            return try httpReply(to: request, body: #"{"mint-0":{"usdPrice":2}}"#)
        }
        let clock = ManualClock()
        let source = JupiterPriceProvider(transport: transport, clock: clock)
        let pricing = Task { try await source.prices(for: (0..<101).map { "mint-\($0)" }) }
        defer { pricing.cancel() }
        var waits = clock.waits.makeAsyncIterator()
        try await clock.advanceToNextWait(&waits)

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: "5")) {
            try await pricing.value
        }

        #expect(await transport.requests.count == 2)
    }

    @Test(arguments: [
        #"{"mint":{"usdPrice":"invalid"}}"#,
        #"{"mint":{"usdPrice":true}}"#,
        #"{"mint":false}"#,
        #"[]"#,
    ])
    func `Invalid price responses fail without inventing a quote`(_ body: String) async {
        let transport = StubTransport { try httpReply(to: $0, body: body) }
        await #expect(throws: RPCError.decoding) {
            try await JupiterPriceProvider(transport: transport).prices(for: ["mint"])
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `Cancelling prices stops the active request and remaining batches`() async throws {
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (pending, release) = AsyncStream<Void>.makeStream()
        defer { startedContinuation.finish(); release.finish() }
        let transport = StubTransport { request in
            startedContinuation.yield(())
            for await _ in pending {}
            try Task.checkCancellation()
            return try httpReply(to: request, body: "{}")
        }
        let source = JupiterPriceProvider(transport: transport)
        let operation = Task {
            try await source.prices(for: (0..<51).map { "mint-\($0)" })
        }
        defer { operation.cancel() }
        var iterator = started.makeAsyncIterator()
        _ = try #require(await iterator.next())

        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await transport.observedCancellation)
        #expect(await transport.requests.count == 1)
    }
}
