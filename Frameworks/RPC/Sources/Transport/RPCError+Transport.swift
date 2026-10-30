import Foundation

extension RPCError {
    /// Creates the error for an HTTP response's unsuccessful status, or `nil` for a 2xx status.
    ///
    /// - Parameter response: The response whose status to check.
    init?(response: HTTPURLResponse) {
        guard !(200..<300).contains(response.statusCode) else { return nil }
        self = .http(statusCode: response.statusCode, retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
    }

    /// Returns a failure with its credentials removed.
    ///
    /// - Parameters:
    ///   - error: A transport, subscription, or decoding failure.
    ///   - redactor: The redactor that removes secrets from text.
    /// - Returns: A `CancellationError` or an ``RPCError`` with redacted text.
    static func sanitized(_ error: any Error, redactor: any TextRedactor) -> any Error {
        if error.isCancellation { return CancellationError() }
        switch error {
        case RPCError.server(let code, let message):
            return RPCError.server(code: code, message: redactor.redact(message))
        case RPCError.http(let status, let retryAfter):
            return RPCError.http(statusCode: status, retryAfter: retryAfter.map(redactor.redact))
        case let error as RPCError: return error
        case is DecodingError: return RPCError.decoding
        default: return RPCError.transport((error as? URLError)?.code ?? .unknown)
        }
    }
}
