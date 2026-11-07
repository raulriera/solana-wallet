import Foundation

/// A client that sends JSON-RPC and JSON requests to an endpoint or to paths below it.
struct HTTPClient: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private let endpoint: URL
    private let transport: any HTTPTransport
    private let redactor: any TextRedactor

    /// Creates an HTTP client for an endpoint.
    ///
    /// - Parameters:
    ///   - endpoint: The provider's HTTP endpoint.
    ///   - transport: The transport that performs HTTP requests.
    ///   - redactor: The redactor that removes secrets from diagnostics.
    init(endpoint: URL, transport: any HTTPTransport, redactor: any TextRedactor) {
        self.endpoint = endpoint
        self.transport = transport
        self.redactor = redactor
    }

    var description: String { "HTTPClient" }

    var debugDescription: String { description }

    var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Sends one request to the endpoint and decodes its response.
    ///
    /// - Parameter request: The RPC method and its parameters.
    /// - Returns: The decoded result.
    /// - Throws: ``RPCError/InvalidResponse/oversized`` for a response body longer than the request's
    ///   ``RPCRequest/maximumResponseLength``, another ``RPCError``, or `CancellationError`.
    @concurrent
    func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        try await send(request, to: endpoint)
    }

    /// Sends one request to a path below the endpoint and decodes its response.
    ///
    /// - Parameters:
    ///   - request: The RPC method and its parameters.
    ///   - path: One or more path components without a leading slash.
    /// - Returns: The decoded result.
    /// - Throws: ``RPCError/InvalidResponse/oversized`` for a response body longer than the request's
    ///   ``RPCRequest/maximumResponseLength``, another ``RPCError``, or `CancellationError`.
    @concurrent
    func send<Request: RPCRequest>(_ request: Request, at path: String) async throws -> Request.Response {
        try await send(request, to: endpoint.appending(path: path))
    }

    /// Gets a path below the endpoint with a query and decodes the response body without a JSON-RPC envelope.
    ///
    /// - Parameters:
    ///   - path: One or more path components without a leading slash.
    ///   - query: The query items.
    ///   - maximumLength: The longest response body, in bytes, to accept.
    ///   - response: The type of the decoded response body.
    /// - Returns: The decoded response body.
    /// - Throws: ``RPCError/InvalidResponse/oversized`` for a longer response body, another ``RPCError``, or
    ///   `CancellationError`.
    @concurrent
    func get<Response: Decodable & Sendable>(
        at path: String, query: [URLQueryItem], maximumLength: Int, decoding response: Response.Type
    ) async throws -> Response {
        try Self.decode(Response.self, from: await get(at: path, query: query, maximumLength: maximumLength))
    }

    /// Gets the endpoint, or a path below it, with a query and returns the response body.
    ///
    /// - Parameters:
    ///   - path: One or more path components without a leading slash, or `nil` for the endpoint itself.
    ///   - query: The query items.
    ///   - headers: The request's header fields.
    ///   - maximumLength: The longest response body, in bytes, to accept.
    /// - Returns: The response body.
    /// - Throws: ``RPCError/InvalidResponse/oversized`` for a longer response body, another ``RPCError``, or
    ///   `CancellationError`.
    @concurrent
    func get(at path: String? = nil, query: [URLQueryItem], headers: [String: String] = [:],
             maximumLength: Int) async throws -> Data {
        try Task.checkCancellation()
        let url = path.map { endpoint.appending(path: $0) } ?? endpoint
        let request = makeRequest(to: url.appending(queryItems: query), method: "GET", headers: headers)
        return try await transport.responseData(for: request, maximumLength: maximumLength, redactor: redactor)
    }

    /// Posts a body to a path below the endpoint, reads a JSON body from the response with any status, and decodes
    /// it without a JSON-RPC envelope.
    ///
    /// - Parameters:
    ///   - body: The request body.
    ///   - path: One or more path components without a leading slash.
    ///   - headers: The request's header fields.
    ///   - maximumLength: The longest response body, in bytes, to accept.
    ///   - read: The step that returns the JSON body from the response body and the HTTP response.
    ///   - response: The type of the decoded JSON body.
    /// - Returns: The decoded JSON body.
    /// - Throws: ``RPCError/InvalidResponse/oversized`` for a longer response body, the error that `read` throws
    ///   without secrets, another ``RPCError``, or `CancellationError`.
    @concurrent
    func post<Response: Decodable & Sendable>(
        _ body: Data,
        at path: String,
        headers: [String: String],
        maximumLength: Int,
        reading read: @Sendable (Data, HTTPURLResponse) throws -> Data,
        decoding response: Response.Type
    ) async throws -> Response {
        try Task.checkCancellation()
        var request = makeRequest(to: endpoint.appending(path: path), method: "POST", headers: headers)
        request.httpBody = body
        let (data, httpResponse) = try await transport.response(
            for: request,
            maximumLength: maximumLength,
            redactor: redactor
        )
        let json: Data
        do {
            json = try read(data, httpResponse)
        } catch {
            throw RPCError.sanitized(error, redactor: redactor)
        }
        return try Self.decode(Response.self, from: json)
    }

    /// Sends one JSON-RPC request to a URL and validates its response envelope.
    ///
    /// - Parameters:
    ///   - request: The RPC method and its parameters.
    ///   - url: The endpoint, or a path below it.
    /// - Returns: The decoded result.
    /// - Throws: ``RPCError/InvalidResponse/oversized`` for a response body longer than the request's
    ///   ``RPCRequest/maximumResponseLength``, another ``RPCError``, or `CancellationError`.
    private func send<Request: RPCRequest>(_ request: Request, to url: URL) async throws -> Request.Response {
        try Task.checkCancellation()
        let id = UUID().uuidString
        let httpRequest = try makeRequest(to: url, body: JSONRPCRequest(id: id, params: request))
        try Task.checkCancellation()

        let data = try await transport.responseData(
            for: httpRequest,
            maximumLength: Request.maximumResponseLength,
            redactor: redactor
        )

        let reply = try Self.decode(JSONRPCResponse<Request.Response>.self, from: data)
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

    /// Decodes a JSON response body.
    ///
    /// - Parameters:
    ///   - type: The type of the decoded value.
    ///   - data: The response body.
    /// - Returns: The decoded value.
    /// - Throws: ``RPCError/decoding``, an ``RPCError`` that the value's decoding throws, or `CancellationError`.
    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let value: Value
        do {
            value = try JSONDecoder().decode(Value.self, from: data)
        } catch {
            if error.isCancellation { throw CancellationError() }
            if let error = error as? RPCError { throw error }
            throw RPCError.decoding
        }
        try Task.checkCancellation()
        return value
    }

    /// Creates a JSON `POST` request with a 30-second timeout.
    ///
    /// - Parameters:
    ///   - url: The request's URL.
    ///   - body: The value to encode as the JSON body.
    /// - Returns: The request.
    /// - Throws: ``RPCError/encoding`` or `CancellationError`.
    private func makeRequest(to url: URL, body: some Encodable) throws -> URLRequest {
        var request = makeRequest(to: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            if error.isCancellation { throw CancellationError() }
            throw RPCError.encoding
        }
        return request
    }

    /// Creates a request with a 30-second timeout.
    ///
    /// - Parameters:
    ///   - url: The request's URL.
    ///   - method: The HTTP method.
    ///   - headers: The request's header fields.
    /// - Returns: The request.
    private func makeRequest(to url: URL, method: String, headers: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        return request
    }
}
