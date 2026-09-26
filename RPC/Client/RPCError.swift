public import Foundation

/// An error encountered while preparing, sending, or interpreting an RPC request.
public enum RPCError: Error, Sendable, Equatable {
    /// The request couldn't be encoded as JSON.
    case encoding
    /// The response couldn't be decoded as the expected type.
    case decoding
    /// The transport failed with the associated URL error code.
    case transport(URLError.Code)
    /// The server returned an unsuccessful HTTP status and an optional retry delay.
    ///
    /// `retryAfter` preserves the sanitized `Retry-After` field, which may contain
    /// a delay in seconds or an HTTP date. The caller decides whether to retry.
    case http(statusCode: Int, retryAfter: String?)
    /// The server returned a JSON-RPC error code and a sanitized message.
    case server(code: Int, message: String)
    /// The server rejected submission during preflight simulation with code `-32002`.
    ///
    /// The message and simulation diagnostics omit the client's credentials.
    case preflight(message: String, simulation: SimulateTransaction.Value)
    /// The response failed JSON-RPC envelope validation.
    case invalidResponse(InvalidResponse)

    /// A reason that a response can't be accepted as the request's result.
    public enum InvalidResponse: Sendable, Equatable {
        /// The transport returned metadata for a non-HTTP response.
        case nonHTTPResponse
        /// The response didn't declare JSON-RPC version 2.0.
        case unsupportedVersion
        /// The response identifier didn't match the request identifier.
        case mismatchedID
        /// The response contained both `result` and `error`, or neither field.
        case invalidEnvelope
    }
}
