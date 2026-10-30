import Foundation

/// A type that performs an HTTP request and returns its response data.
protocol HTTPTransport: Sendable {
    /// Performs a request and returns its response data.
    ///
    /// - Parameter request: The request to perform.
    /// - Returns: The response body and metadata.
    /// - Throws: A transport error.
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// An HTTP transport backed by an ephemeral URL session.
struct URLSessionTransport: HTTPTransport {
    private let session = URLSession(configuration: .ephemeral)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
