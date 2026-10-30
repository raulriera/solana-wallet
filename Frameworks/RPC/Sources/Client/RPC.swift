/// A type that sends typed remote procedure calls.
public protocol RPC: Sendable {
    var network: Network { get }

    /// The additional payments that a submission requires, or `nil` for none.
    var submissionRequirements: SubmissionRequirements? { get }

    /// Sends a request and returns its decoded response.
    ///
    /// - Parameter request: The RPC method and its parameters.
    /// - Returns: The decoded response.
    /// - Throws: An ``RPCError`` or `CancellationError`.
    func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response
}

extension RPC {
    public var submissionRequirements: SubmissionRequirements? { nil }
}

/// A typed RPC method whose encoded value supplies its parameters.
public protocol RPCRequest: Encodable, Sendable {
    /// The type decoded from the response's `result` field.
    associatedtype Response: Decodable & Sendable

    /// The JSON-RPC method name.
    static var method: String { get }
}
