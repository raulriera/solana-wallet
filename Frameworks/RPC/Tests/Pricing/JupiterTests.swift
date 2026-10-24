import Foundation
import Testing
@testable import RPC

/// Exercises the real Jupiter adapter with recorded HTTP inputs and controlled response bodies.
struct JupiterTests {
    /// Verifies exact decimal decoding, normalized fields, and omission of unavailable prices.
    @Test
    func `Prices preserve decimal precision and keep unavailable quotes absent`() async throws {
        let transport = StubTransport { request in
            try httpReply(to: request, body: #"""
                {"mint-a":{"usdPrice":0.12345678901234567890123456789012,"blockId":9007199254740993,"decimals":9},
                 "mint-b":{"usdPrice":0},"metadata-only":{"createdAt":"2025-01-01T00:00:00Z","liquidity":0.12,"decimals":6},
                 "null-price":{"usdPrice":null},"null-record":null}
                """#)
        }
        let source: any PriceProviding = Jupiter(apiKey: "fixture-key", transport: transport)

        let quotes = try await source.prices(for: ["mint-a", "mint-b", "metadata-only", "null-price", "null-record", "unpriced"])

        #expect(quotes.count == 2)
        let first = try #require(quotes["mint-a"])
        #expect(first.pricePerUnit == Decimal(string: "0.12345678901234567890123456789012"))
        #expect(first.currency == "USD")
        #expect(quotes["mint-b"]?.pricePerUnit == 0)
        #expect(quotes["unpriced"] == nil)
        #expect(quotes["metadata-only"] == nil)
        #expect(quotes["null-price"] == nil)
        #expect(quotes["null-record"] == nil)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.url?.host() == "api.jup.ag")
        #expect(request.url?.path() == "/price/v3")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "fixture-key")
        #expect(request.url?.absoluteString.contains("fixture-key") == false)
    }

    /// Verifies the 24-hour change arrives as a fraction, and that a missing or malformed change stays unknown
    /// without discarding its price.
    @Test
    func `Quotes carry the 24-hour change as a fraction and leave a bad one unknown`() async throws {
        let transport = StubTransport { request in
            try httpReply(to: request, body: #"""
                {"rising":{"usdPrice":2,"priceChange24h":1.29},"falling":{"usdPrice":3,"priceChange24h":-3.47},
                 "missing":{"usdPrice":4},"malformed":{"usdPrice":5,"priceChange24h":"soon"}}
                """#)
        }
        let quotes = try await Jupiter(transport: transport).prices(for: ["rising", "falling", "missing", "malformed"])

        #expect(quotes["rising"]?.dayChange == Decimal(string: "0.0129"))
        #expect(quotes["falling"]?.dayChange == Decimal(string: "-0.0347"))
        let missing = try #require(quotes["missing"])
        #expect(missing.pricePerUnit == 4)
        #expect(missing.dayChange == nil)
        let malformed = try #require(quotes["malformed"])
        #expect(malformed.pricePerUnit == 5)
        #expect(malformed.dayChange == nil)
    }

    /// Verifies callers can supply multiple batches without knowing Jupiter's request limit.
    /// - Parameter authenticated: Whether the provider uses the free-key request budget.
    @Test(arguments: [false, true])
    func `Price batches respect the keyless and free-key budgets`(authenticated: Bool) async throws {
        let transport = StubTransport { request in
            let values = try requestedMints(request).map { #""\#($0)":{"usdPrice":1}"# }
            return try httpReply(to: request, body: "{" + values.joined(separator: ",") + "}")
        }
        let mints = (0..<51).map { "mint-\($0)" }
        let startedAt = ContinuousClock.now
        let source = Jupiter(apiKey: authenticated ? "fixture-key" : nil, transport: transport)
        let quotes = try await source.prices(for: mints + mints)

        let interval: Duration = authenticated ? .milliseconds(1_500) : .seconds(3)
        #expect(startedAt.duration(to: .now) >= interval)
        #expect(Set(quotes.keys) == Set(mints))
        let requests = await transport.requests
        #expect(try requests.map { try requestedMints($0).count } == [50, 1])
        #expect(try requests.flatMap(requestedMints) == mints)
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "x-api-key") == (authenticated ? "fixture-key" : nil)
        })
    }

    /// Verifies copied providers share pacing across separate lookups and every batch.
    @Test(.timeLimit(.minutes(1)))
    func `Provider copies share the price budget across calls and batches`() async throws {
        let clock = ManualClock()
        let startedAt = clock.now
        let transport = StubTransport { try httpReply(to: $0, body: "{}") }
        let source = Jupiter(transport: transport, pacer: RequestPacer(interval: .seconds(3), clock: clock))
        _ = try await source.prices(for: ["initial"])
        let copy = source
        async let operation = copy.prices(for: (0..<51).map { "mint-\($0)" })
        var waits = clock.waits.makeAsyncIterator()

        let first = try #require(await waits.next())
        #expect(first == startedAt.advanced(by: .seconds(3)))
        #expect(await transport.requests.count == 1)
        clock.advance(to: first)
        let second = try #require(await waits.next())
        #expect(second == first.advanced(by: .seconds(3)))
        #expect(await transport.requests.count == 2)
        clock.advance(to: second)
        _ = try await operation

        #expect(try await transport.requests.map { try requestedMints($0).count } == [1, 50, 1])
    }

    /// Verifies cancelling a queued batch prevents its HTTP attempt and preserves the next slot.
    @Test(.timeLimit(.minutes(1)))
    func `Cancelling a waiting batch stops without consuming a price request`() async throws {
        let clock = ManualClock()
        let transport = StubTransport { try httpReply(to: $0, body: "{}") }
        let source = Jupiter(transport: transport, pacer: RequestPacer(interval: .seconds(3), clock: clock))
        let operation = Task { try await source.prices(for: (0..<51).map { "mint-\($0)" }) }
        defer { operation.cancel() }
        var waits = clock.waits.makeAsyncIterator()
        let deadline = try #require(await waits.next())
        #expect(await transport.requests.count == 1)

        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await transport.requests.count == 1)

        #expect(try await source.prices(for: []).isEmpty)
        async let next = source.prices(for: ["next"])
        #expect(await waits.next() == deadline)
        clock.advance(to: deadline)
        _ = try await next
        #expect(await transport.requests.count == 2)
    }

    /// Verifies an empty set doesn't consume provider requests.
    @Test
    func `Empty price requests do not access the network`() async throws {
        let transport = StubTransport { try httpReply(to: $0, body: "{}") }
        #expect(try await Jupiter(transport: transport).prices(for: []).isEmpty)
        #expect(await transport.requests.isEmpty)
    }

    /// Verifies a later batch failure prevents partial results, retries, and subsequent requests.
    @Test
    func `Rate limits fail the price lookup without retries or partial success`() async throws {
        let transport = StubTransport { request in
            if try requestedMints(request).first == "mint-50" {
                return try httpReply(to: request, body: "{}", status: 429,
                                      headers: ["Retry-After": "5 fixture-key"])
            }
            return try httpReply(to: request, body: #"{"mint-0":{"usdPrice":2}}"#)
        }
        let source = Jupiter(apiKey: "fixture-key", transport: transport)

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: "5 [redacted]")) {
            try await source.prices(for: (0..<101).map { "mint-\($0)" })
        }

        #expect(await transport.requests.count == 2)
        #expect(!String(describing: source).contains("fixture-key"))
        #expect(!String(reflecting: source).contains("fixture-key"))
    }

    /// Verifies malformed or unrelated values can't become a valid quote.
    /// - Parameter body: An invalid provider response.
    @Test(arguments: [
        #"{"mint":{"usdPrice":-1}}"#,
        #"{"mint":{"usdPrice":"invalid"}}"#,
        #"{"mint":{"usdPrice":true}}"#,
        #"{"mint":false}"#,
        #"{"different-mint":{"usdPrice":1}}"#,
        #"{"different-mint":null}"#,
        #"[]"#,
    ])
    func `Invalid price responses fail without inventing a quote`(_ body: String) async {
        let transport = StubTransport { try httpReply(to: $0, body: body) }
        await #expect(throws: RPCError.decoding) {
            try await Jupiter(transport: transport).prices(for: ["mint"])
        }
    }

    /// Verifies cancellation reaches the active transport and prevents the next batch.
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
        let source = Jupiter(transport: transport)
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

    /// Verifies provider-specific credentials in transport diagnostics don't escape to consumers.
    @Test
    func `Price transport failures omit credential-bearing diagnostics`() async {
        let transport = StubTransport { _ in
            throw URLError(.notConnectedToInternet, userInfo: [NSLocalizedDescriptionKey: "fixture-key"])
        }
        await #expect(throws: RPCError.transport(.notConnectedToInternet)) {
            try await Jupiter(apiKey: "fixture-key", transport: transport).prices(for: ["mint"])
        }
    }
}

/// Reads the requested mint addresses from Jupiter's encoded query.
/// - Parameter request: The outgoing price request.
/// - Returns: The addresses in their requested order.
/// - Throws: A test prerequisite error if the query is missing.
private func requestedMints(_ request: URLRequest) throws -> [String] {
    let url = try #require(request.url)
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    let ids = try #require(query?.first { $0.name == "ids" }?.value)
    return ids.split(separator: ",").map(String.init)
}
