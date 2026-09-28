import Foundation

/// A client that sends typed JSON-RPC requests to Helius on a selected Solana network.
public struct HeliusRPC: RPC, CustomStringConvertible, CustomDebugStringConvertible {
    /// The Solana network that receives the client's requests.
    public let network: Network

    private let client: HTTPClient

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
        client = HTTPClient(endpoint: endpoint, transport: transport,
                            redactor: redactor ?? SecretRedactor(secrets: [apiKey, endpoint.absoluteString]))
    }

    /// A textual representation that identifies the network and omits credentials.
    public var description: String { "HeliusRPC(\(network))" }

    /// A debugging representation that omits the client's credentials.
    public var debugDescription: String { description }

    /// Sends one typed request without automatically retrying it.
    ///
    /// - Parameter request: The RPC method and its parameters.
    /// - Returns: The validated and decoded response.
    /// - Throws: An `RPCError` or `CancellationError`.
    public func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        try await client.send(request)
    }
}
