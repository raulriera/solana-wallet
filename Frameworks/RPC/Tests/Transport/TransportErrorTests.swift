import Foundation
import Testing
@testable import RPC

/// Verifies how HTTP statuses and transport failures become the errors that consumers receive.
struct TransportErrorTests {
    /// The redaction policy for a provider whose key is `fixture-key`.
    private let redactor = SecretRedactor(secrets: ["fixture-key"])

    /// Verifies that an unsuccessful status becomes an HTTP error with its retry delay.
    ///
    /// - Parameter status: A status outside the 2xx range.
    /// - Throws: An error if the fixture response can't be created.
    @Test(arguments: [301, 401, 429, 503])
    func `Unsuccessful statuses become HTTP errors with their retry delay`(status: Int) throws {
        let response = try response(status: status, headers: ["Retry-After": "5"])

        #expect(RPCError(response: response) == .http(statusCode: status, retryAfter: "5"))
    }

    /// Verifies that a successful status is not an error.
    ///
    /// - Parameter status: A status in the 2xx range.
    /// - Throws: An error if the fixture response can't be created.
    @Test(arguments: [200, 204, 299])
    func `Successful statuses are not errors`(status: Int) throws {
        let response = try response(status: status, headers: [:])

        #expect(RPCError(response: response) == nil)
    }

    /// Verifies that sanitizing keeps cancellation as cancellation.
    ///
    /// - Parameter error: A failure that reports cancellation.
    @Test(arguments: [CancellationError(), URLError(.cancelled)] as [any Error])
    func `Sanitizing keeps cancellation as cancellation`(_ error: any Error) {
        #expect(RPCError.sanitized(error, redactor: redactor) is CancellationError)
    }

    /// Verifies that RPC errors keep their case while provider text loses the key.
    ///
    /// - Parameters:
    ///   - error: An RPC error as a provider or transport reported it.
    ///   - expected: The same error without the key.
    @Test(arguments: [
        (RPCError.server(code: -32000, message: "fixture-key failed"),
         RPCError.server(code: -32000, message: "[redacted] failed")),
        (.http(statusCode: 429, retryAfter: "fixture-key"), .http(statusCode: 429, retryAfter: "[redacted]")),
        (.invalidResponse(.mismatchedID), .invalidResponse(.mismatchedID)),
    ])
    func `Sanitizing keeps RPC errors and redacts their provider text`(_ error: RPCError, expected: RPCError) {
        #expect(RPCError.sanitized(error, redactor: redactor) as? RPCError == expected)
    }

    /// Verifies that other failures keep only a decoding case or a URL error code, without their details.
    ///
    /// - Parameters:
    ///   - error: A Foundation, decoding, or other failure that may carry an authenticated URL.
    ///   - expected: The detail-free RPC error.
    @Test(arguments: [
        (URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "fixture-key"]), RPCError.transport(.timedOut)),
        (DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "fixture-key")), .decoding),
        (CocoaError(.fileNoSuchFile), .transport(.unknown)),
    ] as [(any Error, RPCError)])
    func `Sanitizing reduces other failures to a case without their details`(_ error: any Error, expected: RPCError) {
        #expect(RPCError.sanitized(error, redactor: redactor) as? RPCError == expected)
    }

    /// Creates a response from the example endpoint.
    ///
    /// - Parameters:
    ///   - status: The HTTP status code.
    ///   - headers: The response's header fields.
    /// - Returns: The fixture response.
    /// - Throws: An error if the fixture response can't be created.
    private func response(status: Int, headers: [String: String]) throws -> HTTPURLResponse {
        let url = try #require(URL(string: "https://rpc.example.com"))
        return try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers))
    }
}
