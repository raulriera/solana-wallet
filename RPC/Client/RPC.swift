/// A type that sends typed remote procedure calls.
public protocol RPC: Sendable {
    /// The Solana network that receives the client's requests.
    var network: Network { get }

    /// Additional payments required for submission, or `nil` for ordinary RPC delivery.
    var submissionRequirements: SubmissionRequirements? { get }

    /// Sends a request and returns the result described by its response type.
    ///
    /// - Parameter request: The RPC method and parameters to send.
    /// - Returns: The decoded response associated with the request.
    /// - Throws: `CancellationError` if the operation is cancelled, or ``RPCError``
    ///   if the request can't be encoded, delivered, validated, or decoded.
    func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response
}

extension RPC {
    /// Ordinary RPC delivery requires no additional service payment.
    public var submissionRequirements: SubmissionRequirements? { nil }
}

/// A typed RPC method whose encoded value supplies its parameters.
///
/// Conforming types encode only the method's `params` value. The client supplies
/// the JSON-RPC version, method name, and request identifier.
public protocol RPCRequest: Encodable, Sendable {
    /// The value decoded from the response's `result` field.
    associatedtype Response: Decodable & Sendable

    /// The JSON-RPC method name sent to the server.
    static var method: String { get }
}
