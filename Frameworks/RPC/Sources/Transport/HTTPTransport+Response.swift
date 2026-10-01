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
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            // Foundation errors may contain authenticated URLs or headers in userInfo.
            throw RPCError.transport((error as? URLError)?.code ?? .unknown)
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw RPCError.invalidResponse(.nonHTTPResponse)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw RPCError.http(
                statusCode: response.statusCode,
                retryAfter: response.value(forHTTPHeaderField: "Retry-After").map { redactor.redact($0) }
            )
        }
        return data
    }
}
