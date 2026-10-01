import Foundation

/// A client that sends typed JSON-RPC requests to Helius on a selected Solana network.
public struct HeliusRPC: RPC, AccountChangeProviding, CustomStringConvertible, CustomDebugStringConvertible {
    /// The Solana network that receives the client's requests.
    public let network: Network

    private let client: HTTPClient
    private let subscriptions: SubscriptionClient

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
    ///   - socket: The factory for an independent wallet subscription connection.
    init(
        apiKey: String,
        network: Network,
        transport: any HTTPTransport,
        redactor: (any TextRedactor)? = nil,
        socket: @escaping @Sendable (URL) -> any WebSocketConnection = { URLSessionSocket(endpoint: $0) }
    ) {
        let host = switch network {
        case .mainnet: "mainnet.helius-rpc.com"
        case .devnet: "devnet.helius-rpc.com"
        }
        let endpoint = URL(string: "https://\(host)/")!
            .appending(queryItems: [URLQueryItem(name: "api-key", value: apiKey)])
        let socketEndpoint = URL(string: "wss://\(host)/")!
            .appending(queryItems: [URLQueryItem(name: "api-key", value: apiKey)])
        let redactor = redactor ?? SecretRedactor(secrets: [apiKey, endpoint.absoluteString, socketEndpoint.absoluteString])
        self.network = network
        client = HTTPClient(endpoint: endpoint, transport: transport,
                            redactor: redactor)
        subscriptions = SubscriptionClient(endpoint: socketEndpoint, connect: socket, redactor: redactor)
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

    /// Observes confirmed SOL and owned token-account changes through standard Solana subscriptions.
    /// - Parameter owner: The wallet address to watch.
    /// - Returns: Increasing confirmed change slots after all subscriptions are acknowledged.
    /// - Throws: A sanitized subscription, transport, timeout, or cancellation error.
    public func changedSlots(for owner: String) async throws -> AsyncThrowingStream<UInt64, any Error> {
        try await subscriptions.changedSlots(for: owner)
    }
}
