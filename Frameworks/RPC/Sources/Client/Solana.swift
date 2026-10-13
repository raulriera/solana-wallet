public import Foundation

/// A client for standard Solana RPC at a public or custom endpoint, without DAS.
public struct Solana: RPC, AccountChangeProviding, SignatureEventProviding, CustomStringConvertible,
                      CustomDebugStringConvertible {
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

    /// Creates a client for a custom endpoint, such as a node or a provider URL that contains its key.
    ///
    /// Subscriptions use the same URL over WSS. The client doesn't check which network the endpoint serves.
    /// - Parameters:
    ///   - endpoint: An HTTPS URL with a host; its port, path, and query are kept.
    ///   - network: The network that the endpoint serves. The default is `mainnet`.
    /// - Returns: `nil` unless the endpoint uses HTTPS and has a host.
    public init?(endpoint: URL, network: Network = .mainnet) {
        self.init(endpoint: endpoint, network: network, transport: URLSessionTransport())
    }

    /// Creates a public endpoint client with an injected HTTP transport.
    ///
    /// - Parameters:
    ///   - network: The network served by the public endpoint.
    ///   - transport: The operation that performs each request.
    ///   - socket: The factory for an independent wallet subscription connection.
    init(network: Network, transport: any HTTPTransport,
         socket: @escaping @Sendable (URL) -> any WebSocketConnection = { URLSessionSocket(endpoint: $0) }) {
        let host = switch network {
        case .mainnet: "api.mainnet.solana.com"
        case .devnet: "api.devnet.solana.com"
        }
        self.init(network: network, endpoint: URL(string: "https://\(host)")!, socketEndpoint: URL(string: "wss://\(host)")!,
                  redactor: SecretRedactor(secrets: []), transport: transport, socket: socket)
    }

    /// Creates a custom endpoint client with an injected HTTP transport.
    ///
    /// Diagnostics omit both URLs and each of their credentials, path components, and query values,
    /// because any of them can hold a key.
    /// - Parameters:
    ///   - endpoint: An HTTPS URL with a host.
    ///   - network: The network that the endpoint serves.
    ///   - transport: The operation that performs each request.
    ///   - socket: The factory for an independent wallet subscription connection.
    /// - Returns: `nil` unless the endpoint uses HTTPS and has a host.
    init?(endpoint: URL, network: Network, transport: any HTTPTransport,
          socket: @escaping @Sendable (URL) -> any WebSocketConnection = { URLSessionSocket(endpoint: $0) }) {
        let endpoint = endpoint.absoluteURL
        guard endpoint.scheme?.lowercased() == "https", endpoint.host()?.isEmpty == false,
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "wss"
        guard let socketEndpoint = components.url else { return nil }
        // A query item without a value, such as `?key`, holds the key in its name.
        let parts = [endpoint.user(), endpoint.password()] + (components.queryItems ?? []).map { $0.value ?? $0.name }
        let secrets = [endpoint.absoluteString, socketEndpoint.absoluteString]
            + endpoint.pathComponents.filter { $0 != "/" } + parts.compactMap(\.self)
        self.init(network: network, endpoint: endpoint, socketEndpoint: socketEndpoint,
                  redactor: SecretRedactor(secrets: secrets), transport: transport, socket: socket)
    }

    /// Creates a client for an HTTP endpoint and the WebSocket endpoint that serves its subscriptions.
    ///
    /// - Parameters:
    ///   - network: The network that the endpoints serve.
    ///   - endpoint: The HTTPS endpoint for requests.
    ///   - socketEndpoint: The WSS endpoint for subscriptions.
    ///   - redactor: The diagnostic redaction policy for both endpoints.
    ///   - transport: The operation that performs each request.
    ///   - socket: The factory for an independent wallet subscription connection.
    private init(network: Network, endpoint: URL, socketEndpoint: URL, redactor: SecretRedactor,
                 transport: any HTTPTransport, socket: @escaping @Sendable (URL) -> any WebSocketConnection) {
        self.network = network
        client = HTTPClient(endpoint: endpoint, transport: transport, redactor: redactor)
        subscriptions = SubscriptionClient(endpoint: socketEndpoint, connect: socket, redactor: redactor)
    }

    /// A textual representation that identifies the network and omits the endpoint.
    public var description: String { "Solana(\(network))" }

    /// A debugging representation that omits the endpoint.
    public var debugDescription: String { description }

    /// Sends one typed request without automatically retrying it.
    ///
    /// - Parameter request: The RPC method and its parameters.
    /// - Returns: The validated and decoded response.
    /// - Throws: An `RPCError` or `CancellationError`.
    public func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        try await client.send(request)
    }

    /// Observes confirmed changes to each account through standard Solana subscriptions on one connection.
    /// - Parameter addresses: The accounts to watch; a repeated address is watched once.
    /// - Returns: Increasing confirmed change slots after all subscriptions are acknowledged.
    /// - Throws: A subscription, transport, timeout, or cancellation error.
    public func changedSlots(for addresses: [String]) async throws -> AsyncThrowingStream<UInt64, any Error> {
        try await subscriptions.changedSlots(for: addresses)
    }

    /// Watches a signature at confirmed commitment and new roots with standard Solana subscriptions on one connection.
    /// - Parameter signature: The base-58 encoded signature of a sent transaction.
    /// - Returns: The transaction's landing and increasing roots after both subscriptions are acknowledged.
    /// - Throws: A sanitized subscription, transport, timeout, or cancellation error.
    public func events(for signature: String) async throws -> AsyncThrowingStream<SignatureEvent, any Error> {
        try await subscriptions.events(for: signature)
    }
}
