/// A type that sends typed remote procedure calls.
public protocol RPC: Sendable {
    var network: Network { get }

    /// The optional features that the provider's server serves.
    ///
    /// - Throws: An error when the capabilities can't be read.
    var capabilities: Capabilities { get async throws }

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

extension RPC {
    /// No optional features.
    public var capabilities: Capabilities { [] }

    /// Throws when the provider doesn't declare a capability.
    ///
    /// - Parameter capability: The capability that the next request needs.
    /// - Throws: ``CapabilityError/missing(_:)`` for a provider without the capability, or the error of
    ///   ``capabilities``.
    func checkCapability(_ capability: Capabilities) async throws {
        guard try await capabilities.contains(capability) else { throw CapabilityError.missing(capability) }
    }
}

extension RPCRequest {
    public static var maximumResponseLength: Int? { nil }

    public func validate(_ response: Response) throws {}
}
