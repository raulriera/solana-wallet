import Foundation

/// The shared single-attempt JSON-RPC transport for provider adapters.
struct HTTPClient: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private let endpoint: URL
    private let transport: any HTTPTransport
    private let redactor: any TextRedactor

    /// Creates an HTTP client without exposing its endpoint in diagnostics.
    ///
    /// - Parameters:
    ///   - endpoint: The provider's HTTP endpoint.
    ///   - transport: The operation that performs each request.
    ///   - redactor: The provider's credential redaction policy.
    init(endpoint: URL, transport: any HTTPTransport, redactor: any TextRedactor) {
        self.endpoint = endpoint
        self.transport = transport
        self.redactor = redactor
    }

    /// A representation that omits the endpoint and credentials.
    var description: String { "HTTPClient" }

    /// A debugging representation that omits the endpoint and credentials.
    var debugDescription: String { description }

    /// Sends one request to the configured endpoint and decodes its response.
    ///
    /// Execution leaves the caller's actor. Each call uses its own encoder,
    /// decoder, and request identifier, with a 30-second request timeout.
    /// The client doesn't retry failed requests.
    ///
    /// - Parameter request: The typed RPC method and its parameters.
    /// - Returns: The method's decoded result, after validating its response envelope.
    /// - Throws: `CancellationError` if the operation is cancelled, or ``RPCError``
    ///   if encoding, transport, HTTP, RPC, decoding, or response validation fails.
    @concurrent
    func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        try Task.checkCancellation()
        let id = UUID().uuidString
        var httpRequest = URLRequest(url: endpoint, timeoutInterval: 30)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            httpRequest.httpBody = try JSONEncoder().encode(JSONRPCRequest(id: id, params: request))
        } catch {
            if error.isCancellation { throw CancellationError() }
            throw RPCError.encoding
        }
        try Task.checkCancellation()

        let data = try await transport.responseData(for: httpRequest, redactor: redactor)

        let reply: JSONRPCResponse<Request.Response>
        do {
            reply = try JSONDecoder().decode(JSONRPCResponse<Request.Response>.self, from: data)
        } catch {
            if error.isCancellation { throw CancellationError() }
            if let error = error as? RPCError { throw error }
            throw RPCError.decoding
        }
        try Task.checkCancellation()
        switch reply.result {
        case .success(let value):
            guard reply.id == id else { throw RPCError.invalidResponse(.mismatchedID) }
            return value
        case .failure(let error):
            guard reply.id == nil || reply.id == id else { throw RPCError.invalidResponse(.mismatchedID) }
            if let simulation = error.simulation {
                throw RPCError.preflight(
                    message: redactor.redact(error.message),
                    simulation: redactor.redact(simulation)
                )
            }
            throw RPCError.server(code: error.code, message: redactor.redact(error.message))
        }
    }
}
