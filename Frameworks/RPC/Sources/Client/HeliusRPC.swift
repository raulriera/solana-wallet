public import Foundation

/// A client that sends typed JSON-RPC requests to Helius on a selected Solana network.
public struct HeliusRPC: RPC, AccountChangeProviding, SignatureEventProviding, LogoProviding,
                         CustomStringConvertible, CustomDebugStringConvertible {
    public var network: Network { rpc.network }

    private let rpc: Solana

    /// The client for the Solana Rings indexer and prover.
    let gateway: HTTPClient

    /// Creates a client for the selected network.
    ///
    /// - Parameters:
    ///   - apiKey: The Helius API key.
    ///   - network: The Solana network to query.
    public init(apiKey: String, network: Network) {
        self.init(apiKey: apiKey, network: network, transport: URLSessionTransport())
    }

    /// Creates a client with an injected transport and subscription connection factory.
    ///
    /// - Parameters:
    ///   - apiKey: The Helius API key.
    ///   - network: The Solana network to query.
    ///   - transport: The transport that performs HTTP requests.
    ///   - socket: The factory for a subscription connection.
    init(
        apiKey: String,
        network: Network,
        transport: any HTTPTransport,
        socket: @escaping @Sendable (URL) -> any WebSocketConnection = { URLSessionSocket(endpoint: $0) }
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
        // swift-format-ignore: NeverForceUnwrap
        let gatewayEndpoint = URL(string: "https://\(host)/v1/zolana")!
            .appending(queryItems: [URLQueryItem(name: "api-key", value: apiKey)])
        let redactor = SecretRedactor(urls: [endpoint, socketEndpoint])
        rpc = Solana(network: network, endpoint: endpoint, socketEndpoint: socketEndpoint,
                     redactor: redactor, transport: transport, socket: socket)
        gateway = HTTPClient(endpoint: gatewayEndpoint, transport: transport, redactor: redactor)
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

    public func logos(for mints: [String]) async throws -> [String: URL] {
        let unique = mints.uniqued()
        let requested = Set(unique)
        var logos: [String: URL] = [:]
        for batch in unique.batches(of: 1_000) {
            try Task.checkCancellation()
            for case let asset? in try await send(GetAssetBatch(ids: batch)) where requested.contains(asset.id) {
                logos[asset.id] = asset.imageURL
            }
        }
        return logos
    }
}
