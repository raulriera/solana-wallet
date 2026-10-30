import Foundation

extension HTTPTransport {
    /// Performs one HTTP request and returns the body of a successful response.
    ///
    /// - Parameters:
    ///   - request: The request to perform.
    ///   - redactor: The redactor that removes secrets from errors.
    /// - Returns: The response body.
    /// - Throws: An ``RPCError`` or `CancellationError`.
    func responseData(for request: URLRequest, redactor: any TextRedactor) async throws -> Data {
        try Task.checkCancellation()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.data(for: request)
        } catch {
            throw RPCError.sanitized(error, redactor: redactor)
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw RPCError.invalidResponse(.nonHTTPResponse)
        }
        if let error = RPCError(response: response) { throw RPCError.sanitized(error, redactor: redactor) }
        return data
    }
}
