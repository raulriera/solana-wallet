import Foundation

/// A client that sends typed JSON-RPC requests to Helius on a selected Solana network.
public struct HeliusRPC: RPC, AccountChangeProviding, SignatureEventProviding, LogoProviding, RingsProviding,
                         CustomStringConvertible, CustomDebugStringConvertible {
    public var network: Network { rpc.network }

    public var capabilities: Capabilities { [.logos, .privateBalances] }

    public var rings: Zolana { rpc.rings }

    private let rpc: SolanaRPC

    /// Creates a client for the selected network.
    ///
    /// - Parameters:
    ///   - apiKey: The Helius API key.
    ///   - network: The Solana network to query.
    public init(apiKey: String, network: Network) {
        self.init(apiKey: apiKey, network: network, transport: URLSessionTransport())
    }

    /// Creates a client with an injected transport, subscription connection factory, and attestation check.
    ///
    /// - Parameters:
    ///   - apiKey: The Helius API key.
    ///   - network: The Solana network to query.
    ///   - transport: The transport that performs HTTP requests.
    ///   - socket: The factory for a subscription connection.
    ///   - verify: The check that returns the key a prover attestation binds to its nonce under the network's policy.
    init(
        apiKey: String,
        network: Network,
        transport: any HTTPTransport,
        socket: @escaping @Sendable (URL) -> any WebSocketConnection = { URLSessionSocket(endpoint: $0) },
        verify: @escaping AttestedProverKey.Verification = AttestedProverKey.verification
    ) {
        let host = switch network {
        case .mainnet: "mainnet.helius-rpc.com"
        case .devnet: "devnet.helius-rpc.com"
        }
        // swift-format-ignore: NeverForceUnwrap
        let endpoint = URL(string: "https://\(host)/")!
            .appending(queryItems: [URLQueryItem(name: "api-key", value: apiKey)])
        // swift-format-ignore: NeverForceUnwrap
        let socketEndpoint = URL(string: "wss://\(host)/")!
            .appending(queryItems: [URLQueryItem(name: "api-key", value: apiKey)])
        let redactor = SecretRedactor(urls: [endpoint, socketEndpoint])
        rpc = SolanaRPC(network: network, endpoint: endpoint, socketEndpoint: socketEndpoint, redactor: redactor,
                        transport: transport, socket: socket, verify: verify)
    }

    public var description: String { "HeliusRPC(\(network))" }

    public var debugDescription: String { description }

    public func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        try await rpc.send(request)
    }

    public func changedSlots(for addresses: [String]) async throws -> AsyncThrowingStream<UInt64, any Error> {
        try await rpc.changedSlots(for: addresses)
    }

    public func events(for signature: String) async throws -> AsyncThrowingStream<SignatureEvent, any Error> {
        try await rpc.events(for: signature)
    }
}
