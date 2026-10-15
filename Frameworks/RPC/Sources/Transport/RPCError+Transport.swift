import Foundation

extension RPCError {
    /// Creates the error for an HTTP response with an unsuccessful status.
    ///
    /// The `Retry-After` field is kept as received; ``sanitized(_:redactor:)`` redacts it.
    /// - Parameter response: The response whose status to check.
    /// - Returns: `nil` for a 2xx status.
    init?(response: HTTPURLResponse) {
        guard !(200..<300).contains(response.statusCode) else { return nil }
        self = .http(statusCode: response.statusCode, retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
    }

    /// Removes authenticated endpoints and provider text from a failure before it crosses the module boundary.
    ///
    /// Foundation errors may contain authenticated URLs or headers in their userInfo, so only their code remains.
    /// - Parameters:
    ///   - error: A transport, subscription, or decoding failure.
    ///   - redactor: The provider's credential redaction policy.
    /// - Returns: Cancellation, an RPC error with redacted provider text, or a transport code without its userInfo.
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
