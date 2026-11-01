import Foundation

/// A type that performs an HTTP request and returns its response data.
protocol HTTPTransport: Sendable {
    /// Performs a request and returns its response data.
    ///
    /// - Parameter request: The request to perform.
    /// - Returns: The response body and metadata.
    /// - Throws: A transport error.
    func data(for request: URLRequest) async throws -> (Data, URLResponse)

    /// Performs a request and returns its response data, refusing a body longer than a limit.
    ///
    /// - Parameters:
    ///   - request: The request to perform.
    ///   - maximumLength: The longest body, in bytes, to accept.
    /// - Returns: The response body and metadata.
    /// - Throws: ``RPCError/InvalidResponse/oversized`` for a longer body, or a transport error.
    func data(for request: URLRequest, maximumLength: Int) async throws -> (Data, URLResponse)
}

extension HTTPTransport {
    /// Performs a request, then refuses its response data if the body is longer than a limit.
    ///
    /// - Parameters:
    ///   - request: The request to perform.
    ///   - maximumLength: The longest body, in bytes, to accept.
    /// - Returns: The response body and metadata.
    /// - Throws: ``RPCError/InvalidResponse/oversized`` for a longer body, or a transport error.
    func data(for request: URLRequest, maximumLength: Int) async throws -> (Data, URLResponse) {
        let (data, response) = try await data(for: request)
        guard data.count <= maximumLength else { throw RPCError.invalidResponse(.oversized) }
        return (data, response)
    }
}

/// An HTTP transport backed by a URL session.
struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    /// Creates a transport with a session for a configuration.
    ///
    /// - Parameter configuration: The session's configuration.
    init(configuration: URLSessionConfiguration = .ephemeral) {
        session = URLSession(configuration: configuration)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    /// Performs a request and reads its body until it ends or grows longer than a limit.
    ///
    /// - Parameters:
    ///   - request: The request to perform.
    ///   - maximumLength: The longest body, in bytes, to accept.
    /// - Returns: The response body and metadata.
    /// - Throws: ``RPCError/InvalidResponse/oversized`` for a declared or read body longer than the limit, or a
    ///   transport error.
    func data(for request: URLRequest, maximumLength: Int) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard response.expectedContentLength <= maximumLength else { throw RPCError.invalidResponse(.oversized) }
        var data = Data()
        data.reserveCapacity(Int(max(response.expectedContentLength, 0)))
        for try await byte in bytes {
            guard data.count < maximumLength else { throw RPCError.invalidResponse(.oversized) }
            data.append(byte)
        }
        return (data, response)
    }
}
