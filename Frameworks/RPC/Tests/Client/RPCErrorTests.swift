import Foundation
import RPC
import Testing

struct RPCErrorTests {
    @Test(arguments: [
        RPCError.transport(.networkConnectionLost), .transport(.timedOut), .http(statusCode: 408, retryAfter: nil),
        .http(statusCode: 500, retryAfter: nil), .http(statusCode: 503, retryAfter: "5"),
        .http(statusCode: 599, retryAfter: nil), .server(code: -32005, message: "Node is behind by 42 slots"),
    ])
    func `Transport failures, timeouts, server errors, and a node that is behind are recoverable`(_ error: RPCError) {
        #expect(error.isRecoverable)
    }

    @Test(arguments: [
        RPCError.http(statusCode: 429, retryAfter: "5"), .server(code: 429, message: "Rate limited"),
        .http(statusCode: 401, retryAfter: nil), .http(statusCode: 403, retryAfter: nil),
        .http(statusCode: 499, retryAfter: nil), .server(code: -32601, message: "Method not found"),
        .server(code: -32603, message: "Internal error"), .invalidResponse(.mismatchedID), .decoding,
    ])
    func `Rate limits, key errors, and other refusals are not recoverable`(_ error: RPCError) {
        #expect(!error.isRecoverable)
    }

    @Test(arguments: [
        (RPCError.http(statusCode: 429, retryAfter: "5"), true), (.server(code: 429, message: "Rate limited"), true),
        (.http(statusCode: 503, retryAfter: nil), false), (.server(code: -32005, message: "Node is behind"), false),
        (.transport(.timedOut), false), (.http(statusCode: 401, retryAfter: nil), false),
    ])
    func `Only status or code 429 is a rate limit`(_ error: RPCError, isRateLimited: Bool) {
        #expect(error.isRateLimited == isRateLimited)
    }
}
