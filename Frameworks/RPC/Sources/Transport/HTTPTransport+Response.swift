import Foundation

extension HTTPTransport {
    /// Performs one HTTP request and returns the body of a successful response.
    ///
    /// - Parameters:
    ///   - request: The request to perform.
    ///   - maximumLength: The longest body, in bytes, to accept, or `nil` for a body of any length.
    ///   - redactor: The redactor that removes secrets from errors.
    /// - Returns: The response body.
    /// - Throws: ``RPCError/InvalidResponse/oversized`` for a longer body,
    ///   ``RPCError/http(statusCode:retryAfter:)`` for an unsuccessful status, another ``RPCError``, or
    ///   `CancellationError`.
    func responseData(
        for request: URLRequest,
        maximumLength: Int? = nil,
        redactor: any TextRedactor
    ) async throws -> Data {
        let (data, response) = try await self.response(for: request, maximumLength: maximumLength, redactor: redactor)
        if let error = RPCError(response: response) { throw RPCError.sanitized(error, redactor: redactor) }
        return data
    }

    /// Performs one HTTP request and returns its body and response with any status.
    ///
    /// - Parameters:
    ///   - request: The request to perform.
    ///   - maximumLength: The longest body, in bytes, to accept, or `nil` for a body of any length.
    ///   - redactor: The redactor that removes secrets from errors.
    /// - Returns: The response body and the HTTP response.
    /// - Throws: ``RPCError/InvalidResponse/oversized`` for a longer body,
    ///   ``RPCError/InvalidResponse/nonHTTPResponse`` for a response without HTTP metadata, another ``RPCError``, or
    ///   `CancellationError`.
    func response(
        for request: URLRequest,
        maximumLength: Int?,
        redactor: any TextRedactor
    ) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let data: Data
        let response: URLResponse
        do {
            if let maximumLength {
                (data, response) = try await self.data(for: request, maximumLength: maximumLength)
            } else {
                (data, response) = try await self.data(for: request)
            }
        } catch {
            throw RPCError.sanitized(error, redactor: redactor)
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw RPCError.invalidResponse(.nonHTTPResponse)
        }
        return (data, response)
    }
}
