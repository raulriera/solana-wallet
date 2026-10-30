import Foundation
import Testing
@testable import RPC

struct TransportErrorTests {
    private let redactor = SecretRedactor(secrets: ["fixture-key"])

    @Test(arguments: [301, 401, 429, 503])
    func `Unsuccessful statuses become HTTP errors with their retry delay`(status: Int) throws {
        let response = try response(status: status, headers: ["Retry-After": "5"])

        #expect(RPCError(response: response) == .http(statusCode: status, retryAfter: "5"))
    }

    @Test(arguments: [200, 204, 299])
    func `Successful statuses are not errors`(status: Int) throws {
        let response = try response(status: status, headers: [:])

        #expect(RPCError(response: response) == nil)
    }

    @Test(arguments: [CancellationError(), URLError(.cancelled)] as [any Error])
    func `Sanitizing keeps cancellation as cancellation`(_ error: any Error) {
        #expect(RPCError.sanitized(error, redactor: redactor) is CancellationError)
    }

    @Test(arguments: [
        (RPCError.server(code: -32000, message: "fixture-key failed"),
         RPCError.server(code: -32000, message: "[redacted] failed")),
        (.http(statusCode: 429, retryAfter: "fixture-key"), .http(statusCode: 429, retryAfter: "[redacted]")),
        (.invalidResponse(.mismatchedID), .invalidResponse(.mismatchedID)),
    ])
    func `Sanitizing keeps RPC errors and redacts their provider text`(_ error: RPCError, expected: RPCError) {
        #expect(RPCError.sanitized(error, redactor: redactor) as? RPCError == expected)
    }

    @Test(arguments: [
        (URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "fixture-key"]), RPCError.transport(.timedOut)),
        (DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "fixture-key")), .decoding),
        (CocoaError(.fileNoSuchFile), .transport(.unknown)),
    ] as [(any Error, RPCError)])
    func `Sanitizing reduces other failures to a case without their details`(_ error: any Error, expected: RPCError) {
        #expect(RPCError.sanitized(error, redactor: redactor) as? RPCError == expected)
    }

    private func response(status: Int, headers: [String: String]) throws -> HTTPURLResponse {
        let url = try #require(URL(string: "https://rpc.example.com"))
        return try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers))
    }
}
