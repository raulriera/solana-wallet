import Foundation

/// A client that sends typed JSON-RPC requests to Helius on a selected Solana network.
public struct HeliusRPC: RPC, CustomStringConvertible, CustomDebugStringConvertible {
    /// The Solana network that receives the client's requests.
    public let network: Network

    private let endpoint: URL
    private let transport: any HTTPTransport
    private let redactor: any TextRedactor

    /// Creates a client with an ephemeral URL session on the selected network.
    ///
    /// - Parameters:
    ///   - apiKey: The caller's Helius API key. The client doesn't persist it.
    ///   - network: The Solana network to query. The default is `mainnet`.
    public init(apiKey: String, network: Network = .mainnet) {
        self.init(apiKey: apiKey, network: network, transport: URLSessionTransport())
    }

    /// Creates a client with an injected transport and redaction policy.
    ///
    /// - Parameters:
    ///   - apiKey: The Helius API key to include in the request URL.
    ///   - network: The Solana network to query.
    ///   - transport: The transport that performs HTTP requests.
    ///   - redactor: The diagnostic redactor, or `nil` to redact the key and endpoint.
    init(
        apiKey: String,
        network: Network,
        transport: any HTTPTransport,
        redactor: (any TextRedactor)? = nil
    ) {
        let host = switch network {
        case .mainnet: "mainnet.helius-rpc.com"
        case .devnet: "devnet.helius-rpc.com"
        }
        let endpoint = URL(string: "https://\(host)/")!
            .appending(queryItems: [URLQueryItem(name: "api-key", value: apiKey)])
        self.network = network
        self.endpoint = endpoint
        self.transport = transport
        self.redactor = redactor ?? SecretRedactor(secrets: [apiKey, endpoint.absoluteString])
    }

    /// A textual representation that identifies the network and omits credentials.
    public var description: String { "HeliusRPC(\(network))" }

    /// A debugging representation that omits the client's credentials.
    public var debugDescription: String { description }

    /// Sends one request to Helius on the selected network and decodes its response.
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
    public func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        try Task.checkCancellation()
        let id = UUID().uuidString
        var httpRequest = URLRequest(url: endpoint, timeoutInterval: 30)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            httpRequest.httpBody = try JSONEncoder().encode(JSONRPCRequest(id: id, params: request))
        } catch {
            throw RPCError.encoding
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: httpRequest)
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            // Foundation errors may contain the authenticated URL in userInfo.
            throw RPCError.transport((error as? URLError)?.code ?? .unknown)
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw RPCError.invalidResponse(.nonHTTPResponse)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw RPCError.http(
                statusCode: response.statusCode,
                retryAfter: response.value(forHTTPHeaderField: "Retry-After").map { redactor.redact($0) }
            )
        }

        let reply: JSONRPCResponse<Request.Response>
        do {
            reply = try JSONDecoder().decode(JSONRPCResponse<Request.Response>.self, from: data)
        } catch let error as RPCError {
            throw error
        } catch {
            throw RPCError.decoding
        }
        guard reply.id == id else {
            throw RPCError.invalidResponse(.mismatchedID)
        }
        switch reply.result {
        case .success(let value):
            return value
        case .failure(let error):
            throw RPCError.server(code: error.code, message: redactor.redact(error.message))
        }
    }
}
