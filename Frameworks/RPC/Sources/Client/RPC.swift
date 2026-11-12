/// A type that sends typed remote procedure calls.
public protocol RPC: Sendable {
    var network: Network { get }

    /// Sends a request and returns its decoded response.
    ///
    /// - Parameter request: The RPC method and its parameters.
    /// - Returns: The decoded response.
    /// - Throws: An ``RPCError`` or `CancellationError`.
    func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response
}

/// A typed RPC method whose encoded value supplies its parameters.
public protocol RPCRequest: Encodable, Sendable {
    /// The type decoded from the response's `result` field.
    associatedtype Response: Decodable & Sendable

    /// The JSON-RPC method name.
    static var method: String { get }

    /// The longest response body, in bytes, to accept, or `nil` for a body of any length.
    static var maximumResponseLength: Int? { get }

    /// Checks that a decoded response answers the request.
    ///
    /// - Parameter response: The decoded response.
    /// - Throws: An ``RPCError/invalidResponse(_:)`` error if the response can't be the request's result.
    func validate(_ response: Response) throws
}

extension RPCRequest {
    public static var maximumResponseLength: Int? { nil }

    public func validate(_ response: Response) throws {}
}
