public import Foundation

/// A client that sends typed JSON-RPC requests to Helius on a selected Solana network.
public struct HeliusRPC: RPC, AccountChangeProviding, SignatureEventProviding, LogoProviding,
                         CustomStringConvertible, CustomDebugStringConvertible {
    /// The Solana network that receives the client's requests.
    public var network: Network { rpc.network }

    /// Standard Solana RPC at the Helius endpoints, which also answer DAS requests.
    private let rpc: Solana

    /// Creates a client with an ephemeral URL session on the selected network.
    ///
    /// - Parameters:
    ///   - apiKey: The caller's Helius API key. The client doesn't persist it.
    ///   - network: The Solana network to query.
    public init(apiKey: String, network: Network) {
        self.init(apiKey: apiKey, network: network, transport: URLSessionTransport())
    }

    /// Creates a client with an injected transport that redacts the key and endpoints from diagnostics.
    ///
    /// - Parameters:
    ///   - apiKey: The Helius API key to include in the request URL.
    ///   - network: The Solana network to query.
    ///   - transport: The transport that performs HTTP requests.
    ///   - socket: The factory for an independent wallet subscription connection.
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
        let endpoint = URL(string: "https://\(host)/")!
            .appending(queryItems: [URLQueryItem(name: "api-key", value: apiKey)])
        let socketEndpoint = URL(string: "wss://\(host)/")!
            .appending(queryItems: [URLQueryItem(name: "api-key", value: apiKey)])
        rpc = Solana(network: network, endpoint: endpoint, socketEndpoint: socketEndpoint,
                     redactor: SecretRedactor(urls: [endpoint, socketEndpoint]), transport: transport, socket: socket)
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
        try await rpc.send(request)
    }

    /// Observes finalized changes to each account through standard Solana subscriptions on one connection.
    /// - Parameter addresses: The accounts to watch; a repeated address is watched once.
    /// - Returns: Increasing finalized change slots after all subscriptions are acknowledged.
    /// - Throws: A sanitized subscription, transport, timeout, or cancellation error.
    public func changedSlots(for addresses: [String]) async throws -> AsyncThrowingStream<UInt64, any Error> {
        try await rpc.changedSlots(for: addresses)
    }

    /// Watches a signature at finalized commitment and new roots with standard Solana subscriptions on one connection.
    /// - Parameter signature: The base-58 encoded signature of a sent transaction.
    /// - Returns: The transaction's landing and increasing roots after both subscriptions are acknowledged.
    /// - Throws: A sanitized subscription, transport, timeout, or cancellation error.
    public func events(for signature: String) async throws -> AsyncThrowingStream<SignatureEvent, any Error> {
        try await rpc.events(for: signature)
    }

    /// Looks up Helius's HTTPS copies of token logos with DAS batch requests of at most 1,000 mints.
    ///
    /// A mint that DAS doesn't know, or whose image Helius doesn't copy, has no entry.
    /// - Parameter mints: Mint addresses; duplicates are ignored.
    /// - Returns: Logo URLs on Helius's CDN, keyed by mint address.
    /// - Throws: An `RPCError` or `CancellationError`.
    public func logos(for mints: [String]) async throws -> [String: URL] {
        let unique = mints.uniqued()
        let requested = Set(unique)
        var logos: [String: URL] = [:]
        for batch in unique.batches(of: 1_000) {
            for case let asset? in try await send(GetAssetBatch(ids: batch)) where requested.contains(asset.id) {
                logos[asset.id] = asset.imageURL
            }
        }
        return logos
    }
}
