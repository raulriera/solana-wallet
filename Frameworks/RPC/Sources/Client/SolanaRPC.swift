public import Foundation

/// A client for standard Solana RPC at a public or custom endpoint.
public struct SolanaRPC: RPC, AccountChangeProviding, SignatureEventProviding, LogoProviding, RingsProviding,
                      CustomStringConvertible, CustomDebugStringConvertible {
    public let network: Network
    public let capabilities: Capabilities
    public let rings: Zolana

    private let client: HTTPClient
    private let subscriptions: SubscriptionClient

    /// Creates a client for a network's public endpoint.
    ///
    /// - Parameter network: The Solana network to query.
    public init(network: Network) {
        self.init(network: network, transport: URLSessionTransport())
    }

    /// Creates a client for a custom endpoint, or `nil` unless the endpoint uses HTTPS and has a host.
    ///
    /// The client sends Solana Rings requests to the endpoint's `v1/spr` path.
    ///
    /// - Parameters:
    ///   - endpoint: An HTTPS URL with a host.
    ///   - network: The network that the endpoint serves.
    ///   - capabilities: The optional features that the endpoint's server serves.
    public init?(endpoint: URL, network: Network, capabilities: Capabilities = []) {
        self.init(endpoint: endpoint, network: network, capabilities: capabilities, transport: URLSessionTransport())
    }

    /// Creates a public endpoint client with an injected HTTP transport.
    ///
    /// - Parameters:
    ///   - network: The network served by the public endpoint.
    ///   - transport: The transport that performs HTTP requests.
    ///   - socket: The factory for a subscription connection.
    init(network: Network, transport: any HTTPTransport,
         socket: @escaping @Sendable (URL) -> any WebSocketConnection = { URLSessionSocket(endpoint: $0) }) {
        let host = switch network {
        case .mainnet: "api.mainnet.solana.com"
        case .devnet: "api.devnet.solana.com"
        }
        // swift-format-ignore: NeverForceUnwrap
        self.init(network: network, endpoint: URL(string: "https://\(host)")!, socketEndpoint: URL(string: "wss://\(host)")!,
                  redactor: SecretRedactor(secrets: []), transport: transport, socket: socket)
    }

    /// Creates a custom endpoint client with an injected HTTP transport, or `nil` for an invalid endpoint.
    ///
    /// - Parameters:
    ///   - endpoint: An HTTPS URL with a host.
    ///   - network: The network that the endpoint serves.
    ///   - capabilities: The optional features that the endpoint's server serves.
    ///   - transport: The transport that performs HTTP requests.
    ///   - socket: The factory for a subscription connection.
    ///   - verify: The check that returns the key a prover attestation binds to its nonce under the network's policy.
    init?(
        endpoint: URL,
        network: Network,
        capabilities: Capabilities = [],
        transport: any HTTPTransport,
        socket: @escaping @Sendable (URL) -> any WebSocketConnection = { URLSessionSocket(endpoint: $0) },
        verify: @escaping AttestedProverKey.Verification = AttestedProverKey.verification
    ) {
        guard let endpoint = endpoint.httpsEndpoint,
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "wss"
        guard let socketEndpoint = components.url else { return nil }
        self.init(
            network: network,
            endpoint: endpoint,
            socketEndpoint: socketEndpoint,
            capabilities: capabilities,
            redactor: SecretRedactor(urls: [endpoint, socketEndpoint]),
            transport: transport,
            socket: socket,
            verify: verify
        )
    }

    /// Creates a client for an HTTP endpoint, the WebSocket endpoint that serves its subscriptions, and the Solana
    /// Rings indexer and prover at the HTTP endpoint's `v1/spr` path.
    ///
    /// - Parameters:
    ///   - network: The network that the endpoints serve.
    ///   - endpoint: The HTTPS endpoint for requests.
    ///   - socketEndpoint: The WSS endpoint for subscriptions.
    ///   - capabilities: The optional features that the endpoints serve.
    ///   - redactor: The redactor that removes secrets from diagnostics.
    ///   - transport: The transport that performs HTTP requests.
    ///   - socket: The factory for a subscription connection.
    ///   - verify: The check that returns the key a prover attestation binds to its nonce under the network's policy.
    init(
        network: Network,
        endpoint: URL,
        socketEndpoint: URL,
        capabilities: Capabilities = [],
        redactor: SecretRedactor,
        transport: any HTTPTransport,
        socket: @escaping @Sendable (URL) -> any WebSocketConnection,
        verify: @escaping AttestedProverKey.Verification = AttestedProverKey.verification
    ) {
        self.network = network
        self.capabilities = capabilities
        client = HTTPClient(endpoint: endpoint, transport: transport, redactor: redactor)
        subscriptions = SubscriptionClient(endpoint: socketEndpoint, connect: socket, redactor: redactor)
        rings = Zolana(
            network: network,
            endpoint: endpoint.appending(path: "v1/spr"),
            redactor: redactor,
            transport: transport,
            verify: verify
        )
    }

    public var description: String { "SolanaRPC(\(network))" }

    public var debugDescription: String { description }

    public func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        try await client.send(request)
    }

    public func changedSlots(for addresses: [String]) async throws -> AsyncThrowingStream<UInt64, any Error> {
        try await subscriptions.changedSlots(for: addresses)
    }

    public func events(for signature: String) async throws -> AsyncThrowingStream<SignatureEvent, any Error> {
        try await subscriptions.events(for: signature)
    }
}
