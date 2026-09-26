import Foundation
import Testing
@testable import RPC

/// Tests typed RPC requests and failures through an injected HTTP transport.
struct HeliusRPCTests {
    private let address = "83astBRguLMdt2h5U1Tpdq5tjFoJ6noeGwaY3mDLVcri"

    /// Verifies the outgoing balance request and its exact lamports and slot.
    ///
    /// The fixture's balance exceeds `Double`'s exact integer range to detect
    /// precision loss during decoding.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("get balance returns wallet lamports and slot")
    func getBalanceReturnsWalletLamportsAndSlot() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":9007199254740993}"#)
        }
        let rpc: any RPC = HeliusRPC(apiKey: "test-key", transport: transport)

        let balance = try await rpc.send(GetBalance(address: address))

        #expect(balance.value == 9_007_199_254_740_993)
        #expect(balance.context.slot == 12345)
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        let parameters = try #require(body["params"] as? [Any])
        #expect(body["jsonrpc"] as? String == "2.0")
        #expect(body["method"] as? String == "getBalance")
        #expect(parameters.count == 2)
        #expect(parameters.first as? String == address)
        #expect((parameters.last as? [String: String])?["commitment"] == "confirmed")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.url?.host() == "devnet.helius-rpc.com")
        #expect(request.timeoutInterval == 30)
        let url = try #require(request.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query == [URLQueryItem(name: "api-key", value: "test-key")])
    }

    /// Verifies the parameterless version request and its decoded node metadata.
    ///
    /// - Throws: An RPC or JSON parsing error, or a failed test prerequisite.
    @Test("get version returns node version and feature set")
    func getVersionReturnsNodeVersionAndFeatureSet() async throws {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"solana-core":"3.0.0","feature-set":2891131721}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", transport: transport)

        let version = try await rpc.send(GetVersion())

        #expect(version.solanaCore == "3.0.0")
        #expect(version.featureSet == 2_891_131_721)
        let request = try #require(await transport.requests.first)
        let body = try requestBody(request)
        #expect(body["method"] as? String == "getVersion")
        #expect((body["params"] as? [String]) == [])
    }

    /// Verifies that an invalid-address rejection preserves the server's code and message.
    @Test("get balance reports an invalid wallet address")
    func getBalanceReportsAnInvalidWalletAddress() async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""error":{"code":-32602,"message":"Invalid param: WrongSize"}"#)
        }
        let rpc = HeliusRPC(apiKey: "test-key", transport: transport)

        await #expect(throws: RPCError.server(code: -32602, message: "Invalid param: WrongSize")) {
            try await rpc.send(GetBalance(address: "invalid-address"))
        }
    }

    /// Verifies that server errors returned by the client omit its API key and endpoint.
    @Test("server errors hide API keys and authenticated URLs")
    func serverErrorsHideAPIKeysAndAuthenticatedURLs() async {
        let apiKey = "test-key"
        let transport = StubTransport { request in
            let endpoint = try #require(request.url?.absoluteString)
            return try reply(to: request,
                             payload: #""error":{"code":-32603,"message":"Request \#(endpoint) failed for \#(apiKey)"}"#)
        }
        let rpc = HeliusRPC(apiKey: apiKey, transport: transport)

        await #expect(throws: RPCError.server(code: -32603, message: "Request [redacted] failed for [redacted]")) {
            try await rpc.send(GetVersion())
        }
    }

    /// Verifies that rate limiting exposes the retry delay without another HTTP attempt.
    @Test("rate limited requests expose the retry delay without retrying")
    func rateLimitedRequestsExposeTheRetryDelayWithoutRetrying() async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""error":{"code":-32005,"message":"Too many requests"}"#,
                      status: 429, headers: ["Retry-After": "5"])
        }
        let rpc = HeliusRPC(apiKey: "test-key", transport: transport)

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: "5")) {
            try await rpc.send(GetBalance(address: address))
        }
        #expect(await transport.requests.count == 1)
    }

    /// Verifies that a response with a different request identifier is rejected.
    @Test("responses belonging to another request are rejected")
    func responsesBelongingToAnotherRequestAreRejected() async {
        let transport = StubTransport { request in
            try reply(to: request, payload: #""result":{"context":{"slot":12345},"value":100}"#,
                      id: "another-request")
        }
        let rpc = HeliusRPC(apiKey: "test-key", transport: transport)

        await #expect(throws: RPCError.invalidResponse(.mismatchedID)) {
            try await rpc.send(GetBalance(address: address))
        }
    }

    /// Verifies transport cancellation after an RPC request has started.
    ///
    /// Streams coordinate request startup and cancellation without timed sleeps.
    ///
    /// - Throws: A test prerequisite error if the transport doesn't signal startup.
    @Test("cancelling a request cancels the HTTP operation", .timeLimit(.minutes(1)))
    func cancellingARequestCancelsTheHTTPOperation() async throws {
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (pending, pendingContinuation) = AsyncStream<Void>.makeStream()
        let transport = StubTransport { _ in
            startedContinuation.yield(())
            for await _ in pending {}
            throw URLError(.cancelled)
        }
        let rpc = HeliusRPC(apiKey: "test-key", transport: transport)
        let task = Task { @concurrent in try await rpc.send(GetVersion()) }
        defer {
            task.cancel()
            startedContinuation.finish()
            pendingContinuation.finish()
        }
        var iterator = started.makeAsyncIterator()
        try #require(await iterator.next() != nil)

        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.observedCancellation)
    }
}

/// A transport that records requests and delegates responses to a fixture closure.
private actor StubTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private(set) var observedCancellation = false
    private let respond: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Creates a transport with a fixture response handler.
    ///
    /// - Parameter respond: The closure that produces a response or throws an error.
    init(respond: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.respond = respond
    }

    /// Records a request and awaits its fixture response.
    ///
    /// - Parameter request: The outgoing request to record and pass to the handler.
    /// - Returns: The response body and metadata produced by the handler.
    /// - Throws: Any error thrown by the fixture handler.
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        do {
            return try await respond(request)
        } catch {
            observedCancellation = Task.isCancelled
            throw error
        }
    }
}

/// Decodes an outgoing request body as a JSON object for assertions.
///
/// - Parameter request: The HTTP request whose body to inspect.
/// - Returns: The request's JSON object, keyed by field name.
/// - Throws: A JSON parsing error, or a test prerequisite error if the body is
///   missing or isn't an object.
private func requestBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// Creates an HTTP fixture response containing a JSON-RPC envelope.
///
/// - Parameters:
///   - request: The request supplying the URL and default response identifier.
///   - payload: A JSON member containing either `result` or `error`.
///   - status: The HTTP status code. The default is 200.
///   - headers: The response header fields. The default is an empty dictionary.
///   - id: A response identifier override, or `nil` to echo the request's identifier.
/// - Returns: The encoded response envelope and its HTTP metadata.
/// - Throws: A JSON parsing error, or a test prerequisite error if required
///   request fields or response metadata can't be obtained.
private func reply(
    to request: URLRequest,
    payload: String,
    status: Int = 200,
    headers: [String: String] = [:],
    id: String? = nil
) throws -> (Data, URLResponse) {
    let requestID = try #require(requestBody(request)["id"] as? String)
    let url = try #require(request.url)
    let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers))
    let data = Data(#"{"jsonrpc":"2.0","id":"\#(id ?? requestID)",\#(payload)}"#.utf8)
    return (data, response)
}
