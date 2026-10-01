import Foundation

/// A client for Solana's public RPC endpoints, which don't provide DAS.
public struct Solana: RPC, AccountChangeProviding {
    /// The network that receives the client's requests.
    public let network: Network

    private let client: HTTPClient
    private let subscriptions: SubscriptionClient

    /// Creates a client for the selected public endpoint.
    ///
    /// - Parameter network: The Solana network to query. The default is `mainnet`.
    public init(network: Network = .mainnet) {
        self.init(network: network, transport: URLSessionTransport())
    }

    /// Creates a public endpoint client with an injected HTTP transport.
    ///
    /// - Parameters:
    ///   - network: The network served by the public endpoint.
    ///   - transport: The operation that performs each request.
    ///   - socket: The factory for an independent wallet subscription connection.
    init(network: Network, transport: any HTTPTransport,
         socket: @escaping @Sendable (URL) -> any WebSocketConnection = { URLSessionSocket(endpoint: $0) }) {
        self.network = network
        let host = switch network {
        case .mainnet: "api.mainnet.solana.com"
        case .devnet: "api.devnet.solana.com"
        }
        client = HTTPClient(endpoint: URL(string: "https://\(host)")!, transport: transport,
                            redactor: SecretRedactor(secrets: []))
        subscriptions = SubscriptionClient(endpoint: URL(string: "wss://\(host)")!, connect: socket,
                                           redactor: SecretRedactor(secrets: []))
    }

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
    /// - Throws: A subscription, transport, timeout, or cancellation error.
    public func changedSlots(for owner: String) async throws -> AsyncThrowingStream<UInt64, any Error> {
        try await subscriptions.changedSlots(for: owner)
    }
}
