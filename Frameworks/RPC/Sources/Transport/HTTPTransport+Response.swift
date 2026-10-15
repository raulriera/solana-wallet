import Foundation

extension HTTPTransport {
    /// Performs one HTTP attempt, preserving cancellation and sanitizing failures.
    /// - Parameters:
    ///   - request: The complete request to perform.
    ///   - redactor: The credential redaction policy for response diagnostics.
    /// - Returns: The body of a successful HTTP response.
    /// - Throws: A transport, HTTP, response-validation, or cancellation error.
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
