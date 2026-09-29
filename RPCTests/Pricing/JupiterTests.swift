import Foundation
import Testing
@testable import RPC

/// Exercises the real Jupiter adapter with recorded HTTP inputs and controlled response bodies.
struct JupiterTests {
    /// Verifies exact decimal decoding, normalized fields, and omission of unavailable prices.
    @Test("prices preserve decimal precision and keep unavailable quotes absent")
    func normalizesQuotes() async throws {
        let transport = StubTransport { request in
            try priceReply(to: request, body: #"{"mint-a":{"usdPrice":0.12345678901234567890123456789012,"blockId":9007199254740993,"decimals":9},"mint-b":{"usdPrice":0}}"#)
        }
        let source: any PriceProviding = Jupiter(apiKey: "fixture-key", transport: transport)
        let startedAt = Date()

        let quotes = try await source.prices(for: ["mint-a", "mint-b", "unpriced"])

        #expect(source.network == .mainnet)
        #expect(quotes.count == 2)
        let first = try #require(quotes["mint-a"])
        #expect(first.pricePerUnit == Decimal(string: "0.12345678901234567890123456789012"))
        #expect(first.currency == "USD")
        #expect(first.blockID == 9_007_199_254_740_993)
        #expect(first.fetchedAt >= startedAt && first.fetchedAt <= Date())
        #expect(quotes["mint-b"]?.pricePerUnit == 0)
        #expect(quotes["mint-b"]?.blockID == nil)
        #expect(quotes["unpriced"] == nil)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.url?.host() == "api.jup.ag")
        #expect(request.url?.path() == "/price/v3")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "fixture-key")
        #expect(request.url?.absoluteString.contains("fixture-key") == false)
    }

    /// Verifies callers can supply multiple batches without knowing Jupiter's request limit.
    @Test("price requests deduplicate mints and batch fifty at a time")
    func batchesUniqueMints() async throws {
        let transport = StubTransport { request in
            let values = try requestedMints(request).map { #""\#($0)":{"usdPrice":1}"# }
            return try priceReply(to: request, body: "{" + values.joined(separator: ",") + "}")
        }
        let mints = (0..<51).map { "mint-\($0)" }
        let quotes = try await Jupiter(transport: transport).prices(for: mints + mints)

        #expect(Set(quotes.keys) == Set(mints))
        let requests = await transport.requests
        #expect(try requests.map { try requestedMints($0).count } == [50, 1])
        #expect(try requests.flatMap(requestedMints) == mints)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "x-api-key") == nil })
    }

    /// Verifies an empty set doesn't consume provider requests.
    @Test("empty price requests do not access the network")
    func emptyRequestStaysLocal() async throws {
        let transport = StubTransport { try priceReply(to: $0, body: "{}") }
        #expect(try await Jupiter(transport: transport).prices(for: []).isEmpty)
        #expect(await transport.requests.isEmpty)
    }

    /// Verifies a later batch failure prevents partial results, retries, and subsequent requests.
    @Test("rate limits fail the price lookup without retries or partial success")
    func rateLimitStopsBatches() async throws {
        let transport = StubTransport { request in
            if try requestedMints(request).first == "mint-50" {
                return try priceReply(to: request, body: "{}", status: 429,
                                      headers: ["Retry-After": "5 fixture-key"])
            }
            return try priceReply(to: request, body: #"{"mint-0":{"usdPrice":2}}"#)
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
    @Test("invalid price responses fail without inventing a quote", arguments: [
        #"{"mint":{"usdPrice":-1}}"#,
        #"{"mint":{"usdPrice":"invalid"}}"#,
        #"{"mint":{"blockId":1}}"#,
        #"{"mint":{"usdPrice":1,"blockId":-1}}"#,
        #"{"different-mint":{"usdPrice":1}}"#,
        #"[]"#,
    ])
    func rejectsInvalidResponse(_ body: String) async {
        let transport = StubTransport { try priceReply(to: $0, body: body) }
        await #expect(throws: RPCError.decoding) {
            try await Jupiter(transport: transport).prices(for: ["mint"])
        }
    }

    /// Verifies cancellation reaches the active transport and prevents the next batch.
    @Test("cancelling prices stops the active request and remaining batches", .timeLimit(.minutes(1)))
    func cancellationStopsRequests() async throws {
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (pending, release) = AsyncStream<Void>.makeStream()
        defer { startedContinuation.finish(); release.finish() }
        let transport = StubTransport { request in
            startedContinuation.yield(())
            for await _ in pending {}
            try Task.checkCancellation()
            return try priceReply(to: request, body: "{}")
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
    @Test("price transport failures omit credential-bearing diagnostics")
    func transportErrorsAreSanitized() async {
        let transport = StubTransport { _ in
            throw URLError(.notConnectedToInternet, userInfo: [NSLocalizedDescriptionKey: "fixture-key"])
        }
        await #expect(throws: RPCError.transport(.notConnectedToInternet)) {
            try await Jupiter(apiKey: "fixture-key", transport: transport).prices(for: ["mint"])
        }
    }
}

/// Creates an ordinary HTTP response without a JSON-RPC envelope.
/// - Parameters:
///   - request: The request supplying the response URL.
///   - body: The provider response body.
///   - status: The HTTP status code.
///   - headers: Additional HTTP response headers.
/// - Returns: The encoded body and HTTP metadata.
/// - Throws: A test prerequisite error if the response can't be created.
private func priceReply(to request: URLRequest, body: String, status: Int = 200,
                        headers: [String: String] = [:]) throws -> (Data, URLResponse) {
    let url = try #require(request.url)
    let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers))
    return (Data(body.utf8), response)
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
