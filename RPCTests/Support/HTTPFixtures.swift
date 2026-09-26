import Foundation
import Testing
@testable import RPC

/// A transport that records requests and delegates responses to a fixture closure.
actor StubTransport: HTTPTransport {
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
func requestBody(_ request: URLRequest) throws -> [String: Any] {
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
func reply(
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
