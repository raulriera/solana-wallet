import Foundation
import RPC
import Testing

/// Verifies which RPC failures can clear without a person's action.
struct RPCErrorTests {
    /// Verifies that lost connections, failing servers, and a node that is behind are recoverable.
    ///
    /// - Parameter error: A transport failure, an HTTP 5xx status, or JSON-RPC code `-32005`.
    @Test(arguments: [
        RPCError.transport(.networkConnectionLost), .transport(.timedOut),
        .http(statusCode: 500, retryAfter: nil), .http(statusCode: 503, retryAfter: "5"),
        .http(statusCode: 599, retryAfter: nil), .server(code: -32005, message: "Node is behind by 42 slots"),
    ])
    func `Transport failures, server errors, and a node that is behind are recoverable`(_ error: RPCError) {
        #expect(error.isRecoverable)
    }

    /// Verifies that rate limits, key errors, and other refusals wait for a person.
    ///
    /// - Parameter error: A failure that an automatic retry can't fix or could make worse.
    @Test(arguments: [
        RPCError.http(statusCode: 429, retryAfter: "5"), .server(code: 429, message: "Rate limited"),
        .http(statusCode: 401, retryAfter: nil), .http(statusCode: 403, retryAfter: nil),
        .http(statusCode: 499, retryAfter: nil), .server(code: -32601, message: "Method not found"),
        .server(code: -32603, message: "Internal error"), .invalidResponse(.mismatchedID), .decoding,
    ])
    func `Rate limits, key errors, and other refusals are not recoverable`(_ error: RPCError) {
        #expect(!error.isRecoverable)
    }

    /// Verifies that status 429 over HTTP and code 429 in a subscription reply are rate limits, and nothing else is.
    ///
    /// - Parameters:
    ///   - error: A failure a request or subscription can report.
    ///   - isRateLimited: Whether the provider is limiting requests.
    @Test(arguments: [
        (RPCError.http(statusCode: 429, retryAfter: "5"), true), (.server(code: 429, message: "Rate limited"), true),
        (.http(statusCode: 503, retryAfter: nil), false), (.server(code: -32005, message: "Node is behind"), false),
        (.transport(.timedOut), false), (.http(statusCode: 401, retryAfter: nil), false),
    ])
    func `Only status or code 429 is a rate limit`(_ error: RPCError, isRateLimited: Bool) {
        #expect(error.isRateLimited == isRateLimited)
    }
}
