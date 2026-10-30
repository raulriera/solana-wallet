public import Foundation

/// A client for standard Solana RPC at a public or custom endpoint.
public struct Solana: RPC, AccountChangeProviding, SignatureEventProviding, CustomStringConvertible,
                      CustomDebugStringConvertible {
    public let network: Network

    private let client: HTTPClient
    private let subscriptions: SubscriptionClient

    /// Creates a client for a network's public endpoint.
    ///
    /// - Parameter network: The Solana network to query.
    public init(network: Network = .mainnet) {
        self.init(network: network, transport: URLSessionTransport())
    }

    /// Creates a client for a custom endpoint, or `nil` unless the endpoint uses HTTPS and has a host.
    ///
    /// - Parameters:
    ///   - endpoint: An HTTPS URL with a host.
    ///   - network: The network that the endpoint serves.
    public init?(endpoint: URL, network: Network) {
        self.init(endpoint: endpoint, network: network, transport: URLSessionTransport())
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
    ///   - transport: The transport that performs HTTP requests.
    ///   - socket: The factory for a subscription connection.
    init?(endpoint: URL, network: Network, transport: any HTTPTransport,
          socket: @escaping @Sendable (URL) -> any WebSocketConnection = { URLSessionSocket(endpoint: $0) }) {
        let endpoint = endpoint.absoluteURL
        guard endpoint.scheme?.lowercased() == "https", endpoint.host()?.isEmpty == false,
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "wss"
        guard let socketEndpoint = components.url else { return nil }
        self.init(network: network, endpoint: endpoint, socketEndpoint: socketEndpoint,
                  redactor: SecretRedactor(urls: [endpoint, socketEndpoint]), transport: transport, socket: socket)
    }

    /// Creates a client for an HTTP endpoint and the WebSocket endpoint that serves its subscriptions.
    ///
    /// - Parameters:
    ///   - network: The network that the endpoints serve.
    ///   - endpoint: The HTTPS endpoint for requests.
    ///   - socketEndpoint: The WSS endpoint for subscriptions.
    ///   - redactor: The redactor that removes secrets from diagnostics.
    ///   - transport: The transport that performs HTTP requests.
    ///   - socket: The factory for a subscription connection.
    init(network: Network, endpoint: URL, socketEndpoint: URL, redactor: SecretRedactor,
         transport: any HTTPTransport, socket: @escaping @Sendable (URL) -> any WebSocketConnection) {
        self.network = network
        client = HTTPClient(endpoint: endpoint, transport: transport, redactor: redactor)
        subscriptions = SubscriptionClient(endpoint: socketEndpoint, connect: socket, redactor: redactor)
    }

    public var description: String { "Solana(\(network))" }

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
