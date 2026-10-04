import Foundation
@testable import RPC

/// Records typed responses from real HTTP requests without replacing their results.
///
/// Keeps public response values in memory; never retains URLs, headers, or credentials.
actor LiveResponses<Request: RPCRequest>: HTTPTransport {
    private let transport = URLSessionTransport()
    private(set) var responses: [Request.Response] = []

    /// Sends the original request and observes successful results for the selected method.
    /// - Parameter request: The real client's HTTP request.
    /// - Returns: The unchanged HTTP response received through URLSession.
    /// - Throws: The underlying transport error, including cancellation.
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = try await transport.data(for: request)
        if let body = request.httpBody,
           let method = try? JSONDecoder().decode(Method.self, from: body),
           method.method == Request.method,
           let envelope = try? JSONDecoder().decode(Envelope.self, from: response.0) {
            responses.append(envelope.result)
        }
        return response
    }

    private struct Method: Decodable {
        let method: String
    }

    private struct Envelope: Decodable {
        let result: Request.Response
    }
}
