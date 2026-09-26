import Foundation

/// A type that performs an HTTP request and returns its response data.
protocol HTTPTransport: Sendable {
    /// Performs a request and waits for its response data.
    ///
    /// - Parameter request: The URL, headers, body, and timeout of the request.
    /// - Returns: The received data and response metadata.
    /// - Throws: A transport error if the request fails or is cancelled.
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// An HTTP transport backed by an ephemeral URL session.
struct URLSessionTransport: HTTPTransport {
    private let session = URLSession(configuration: .ephemeral)

    /// Downloads the response to a request using the transport's URL session.
    ///
    /// Cancellation of the calling task cancels the session's data task.
    ///
    /// - Parameter request: The URL request to perform.
    /// - Returns: The response body and its associated metadata.
    /// - Throws: A `URLError` if the transfer fails, times out, or is cancelled.
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
