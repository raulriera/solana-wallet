import Foundation
import Testing
@testable import RPC

/// Price HTTP fixtures decoded by the real Jupiter adapter.
actor PriceResponses: HTTPTransport {
    private(set) var requests: [[String]] = []
    private let status: Int
    private let respond: @Sendable ([String]) async throws -> Data

    /// The real price adapter backed by this fixture's HTTP boundary.
    nonisolated var client: Jupiter { Jupiter(transport: self) }

    /// Creates isolated price responses without replacing the provider's decoding or batching.
    /// - Parameters:
    ///   - status: The HTTP status for each response.
    ///   - respond: The response supplier, which may suspend or fail.
    init(status: Int = 200, respond: @escaping @Sendable ([String]) async throws -> Data) {
        self.status = status
        self.respond = respond
    }

    /// Records requested mints and returns the configured HTTP price response.
    /// - Parameter request: The request encoded by Jupiter.
    /// - Returns: The response body and status, with a retry hint for rate-limit checks.
    /// - Throws: A fixture, transport, or cancellation error.
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let ids = try #require(components.queryItems?.first { $0.name == "ids" }?.value)
        let mints = ids.split(separator: ",").map(String.init)
        requests.append(mints)
        let body = try await respond(mints)
        return (body, try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                                 headerFields: ["Retry-After": "2"])))
    }
}
