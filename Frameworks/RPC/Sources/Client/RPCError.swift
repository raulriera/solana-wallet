public import Foundation

/// An error encountered while preparing, sending, or interpreting an RPC request.
public enum RPCError: Error, Sendable, Equatable {
    case encoding
    case decoding
    case transport(URLError.Code)
    /// An unsuccessful HTTP status and the `Retry-After` value, which holds seconds or an HTTP date.
    case http(statusCode: Int, retryAfter: String?)
    /// A JSON-RPC error that the server returned.
    case server(code: Int, message: String)
    /// A submission that the server rejected during preflight simulation.
    case preflight(message: String, simulation: SimulateTransaction.Value)
    case invalidResponse(InvalidResponse)

    /// A reason that a response can't be accepted as the request's result.
    public enum InvalidResponse: Sendable, Equatable {
        case nonHTTPResponse
        case unsupportedVersion
        case mismatchedID
        /// The response contained both `result` and `error`, or neither.
        case invalidEnvelope
        /// A page repeated a cursor or returned one without rows.
        case invalidCursor
        /// The proofs don't match the requested leaves, their order, or the tree.
        case mismatchedProofs
        /// The prover's attestation doesn't prove that the expected enclave holds its key.
        case untrustedProver
    }

    /// Whether the failure can clear without the person's action.
    public var isRecoverable: Bool {
        switch self {
        case .transport, .http(statusCode: 500..<600, retryAfter: _), .server(code: -32005, message: _): true
        case .encoding, .decoding, .http, .server, .preflight, .invalidResponse: false
        }
    }

    public var isRateLimited: Bool {
        switch self {
        case .http(statusCode: 429, retryAfter: _), .server(code: 429, message: _): true
        case .encoding, .decoding, .transport, .http, .server, .preflight, .invalidResponse: false
        }
    }
}
