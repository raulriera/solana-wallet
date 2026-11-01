import CryptoKit
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
    /// - Throws: An ``RPCError`` or `CancellationError`.
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
    /// - Throws: An ``RPCError`` or `CancellationError`.
    @concurrent
    func send<Request: RPCRequest>(_ request: Request, at path: String) async throws -> Request.Response {
        try await send(request, to: try url(at: path))
    }

    /// Posts a JSON body to a path below the endpoint and decodes the response body without a JSON-RPC envelope.
    ///
    /// - Parameters:
    ///   - body: The value to send as the JSON request body.
    ///   - path: One or more path components without a leading slash.
    ///   - headers: Header fields to add to `Content-Type: application/json`.
    ///   - response: The type of the decoded response body.
    /// - Returns: The decoded response body.
    /// - Throws: An ``RPCError`` or `CancellationError`.
    @concurrent
    func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ body: Body, at path: String, headers: [String: String], decoding response: Response.Type
    ) async throws -> Response {
        try Task.checkCancellation()
        let data = try await transport.responseData(
            for: try makeRequest(to: try url(at: path), body: body, headers: headers), redactor: redactor
        )
        return try decode(Response.self, from: data)
    }

    /// Gets a path below the endpoint with a query and decodes the response body without a JSON-RPC envelope.
    ///
    /// - Parameters:
    ///   - path: One or more path components without a leading slash.
    ///   - query: The query items to add after the endpoint's query.
    ///   - maximumLength: The longest response body, in bytes, to accept.
    ///   - response: The type of the decoded response body.
    /// - Returns: The decoded response body.
    /// - Throws: ``RPCError/InvalidResponse/oversized`` for a longer response body, another ``RPCError``, or
    ///   `CancellationError`.
    @concurrent
    func get<Response: Decodable & Sendable>(
        at path: String, query: [URLQueryItem], maximumLength: Int, decoding response: Response.Type
    ) async throws -> Response {
        try Task.checkCancellation()
        let request = makeRequest(to: try url(at: path).appending(queryItems: query), method: "GET")
        let data = try await transport.responseData(for: request, maximumLength: maximumLength, redactor: redactor)
        return try decode(Response.self, from: data)
    }

    /// Posts a JSON body encrypted to the Solana Rings prover's key to a path below the endpoint and decrypts the
    /// prover's answer.
    ///
    /// - Parameters:
    ///   - body: The value to encrypt as the JSON request body.
    ///   - path: One or more path components without a leading slash.
    ///   - headers: Header fields to add to the encrypted request.
    ///   - maximumLength: The longest response body, in bytes, to accept.
    ///   - key: The prover's attested HPKE key.
    /// - Returns: The prover's decrypted status and body.
    /// - Throws: ``RPCError/encoding`` for a body or request that can't be encrypted,
    ///   ``RPCError/InvalidResponse/oversized`` for a longer response body, an ``RPCError`` for an answer that
    ///   doesn't decrypt or an unencrypted refusal, or `CancellationError`.
    @concurrent
    func post(
        sealing body: some Encodable & Sendable,
        at path: String,
        headers: [String: String],
        maximumLength: Int,
        to key: Curve25519.KeyAgreement.PublicKey
    ) async throws -> SealedProverRequest.Answer {
        try Task.checkCancellation()
        let request = try makeRequest(to: try url(at: path), body: body, headers: headers)
        let sealed = try SealedProverRequest(sealing: request, below: endpoint, to: key)
        let (data, response) = try await transport.response(
            for: sealed.request,
            maximumLength: maximumLength,
            redactor: redactor
        )
        do {
            return try sealed.open(data, response: response)
        } catch {
            throw RPCError.sanitized(error, redactor: redactor)
        }
    }

    /// Sends one JSON-RPC request to a URL and validates its response envelope.
    ///
    /// - Parameters:
    ///   - request: The RPC method and its parameters.
    ///   - url: The endpoint, or a path below it.
    /// - Returns: The decoded result.
    /// - Throws: An ``RPCError`` or `CancellationError`.
    private func send<Request: RPCRequest>(_ request: Request, to url: URL) async throws -> Request.Response {
        try Task.checkCancellation()
        let id = UUID().uuidString
        let httpRequest = try makeRequest(to: url, body: JSONRPCRequest(id: id, params: request), headers: [:])
        try Task.checkCancellation()

        let data = try await transport.responseData(for: httpRequest, redactor: redactor)

        let reply = try decode(JSONRPCResponse<Request.Response>.self, from: data)
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
    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
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
    ///   - headers: Header fields to add to `Content-Type: application/json`.
    /// - Returns: The request.
    /// - Throws: ``RPCError/encoding`` or `CancellationError`.
    private func makeRequest(to url: URL, body: some Encodable, headers: [String: String]) throws -> URLRequest {
        var request = makeRequest(to: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
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
    /// - Returns: The request.
    private func makeRequest(to url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        return request
    }

    /// Appends a path to the endpoint's path, keeping its query.
    ///
    /// - Parameter path: One or more path components without a leading slash.
    /// - Returns: The path's URL.
    /// - Throws: ``RPCError/encoding`` for an invalid URL.
    private func url(at path: String) throws -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw RPCError.encoding
        }
        let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = base + "/" + path
        guard let url = components.url else { throw RPCError.encoding }
        return url
    }
}
