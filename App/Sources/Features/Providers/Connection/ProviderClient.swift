import Foundation
import RPC

/// Sends one network's requests through the selected RPC provider, and its private-note reads and proofs through the
/// network's Solana Rings provider.
nonisolated struct ProviderClient: RPC, AccountChangeProviding, SignatureEventProviding, LogoProviding,
    PrivateNoteProviding, ProofProviding {
    /// A provider that receives requests, with what it needs to accept them.
    nonisolated enum Endpoint: Hashable, Sendable {
        /// Solana's public RPC.
        case solana
        case helius(key: String)
        case custom(URL)
    }

    /// A provider's client for requests, account changes, and signature watches.
    typealias Client = any RPC & AccountChangeProviding & SignatureEventProviding

    let network: Network
    private let providers: ProviderStore
    private let clients: Clients
    /// The Solana Rings indexer and prover of the network, kept across provider and key changes.
    private let rings: any PrivateNoteProviding & ProofProviding

    /// Creates a client that reads the selected provider before every request.
    ///
    /// - Parameters:
    ///   - network: The network that receives every request and subscription.
    ///   - providers: The provider settings to read.
    ///   - rings: The provider that reads the network's private notes and proves its private transfers.
    ///   - client: A function that creates the client for an endpoint on a network.
    init(network: Network, providers: ProviderStore, rings: any PrivateNoteProviding & ProofProviding,
         client: @escaping @Sendable (Endpoint, Network) -> Client? = Self.client(for:on:)) {
        self.network = network
        self.providers = providers
        self.rings = rings
        clients = Clients(network: network, make: client)
    }

    func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        try await perform { try await $0.send(request) }
    }

    func changedSlots(for addresses: [String]) async throws -> AsyncThrowingStream<UInt64, any Error> {
        try await perform { try await $0.changedSlots(for: addresses) }
    }

    func events(for signature: String) async throws -> AsyncThrowingStream<SignatureEvent, any Error> {
        try await perform { try await $0.events(for: signature) }
    }

    func logos(for mints: [String]) async throws -> [String: URL] {
        try await perform { client in
            guard let client = client as? any LogoProviding else { return [:] }
            return try await client.logos(for: mints)
        }
    }

    func shieldedTransactions(taggedWith tags: [[UInt8]], after position: NoteSyncPosition?) async throws
        -> ShieldedTransactionBatch {
        try await performRings { try await $0.shieldedTransactions(taggedWith: tags, after: position) }
    }

    func shieldedTransactions(spending nullifiers: [[UInt8]]) async throws -> [ShieldedTransaction] {
        try await performRings { try await $0.shieldedTransactions(spending: nullifiers) }
    }

    func merkleProofs(for leaves: [[UInt8]], inTree tree: String) async throws -> [MerkleProof] {
        try await performRings { try await $0.merkleProofs(for: leaves, inTree: tree) }
    }

    func proveTransfer(_ request: IndexedTransferProofRequest) async throws -> IndexedTransferProof {
        try await performRings { try await $0.proveTransfer(request) }
    }

    /// Runs a private-note read or proof on the Solana Rings provider once the selected provider serves this network.
    ///
    /// - Parameter operation: The read or proof.
    /// - Returns: The operation's result.
    /// - Throws: The error of ``endpoint()``, ``ProviderClientError/unusableEndpoint`` for a saved endpoint that can't
    ///   be used, or the operation's error unchanged.
    private func performRings<Value: Sendable>(
        _ operation: (any PrivateNoteProviding & ProofProviding) async throws -> Value
    ) async throws -> Value {
        _ = try await clients.client(for: endpoint())
        return try await operation(rings)
    }

    /// Runs an operation on the selected provider's client.
    ///
    /// - Parameter operation: The work to send to the provider.
    /// - Returns: The operation's result.
    /// - Throws: The operation's error, with Helius's key rejections as ``ProviderClientError/invalidKey``.
    private func perform<Value: Sendable>(
        _ operation: (Client) async throws -> Value
    ) async throws -> Value {
        let endpoint = try await endpoint()
        let client = try await clients.client(for: endpoint)
        do {
            return try await operation(client)
        } catch {
            guard case .helius = endpoint, (error as? RPCError)?.rejectsKey == true else { throw error }
            throw ProviderClientError.invalidKey
        }
    }

    /// Reads the selected provider and, for Helius, its key.
    ///
    /// - Returns: The endpoint that receives the next request.
    /// - Throws: ``ProviderClientError/missingKey`` when Helius is selected without a key,
    ///   ``ProviderClientError/unsupportedNetwork`` when a custom RPC is selected off mainnet,
    ///   ``ProviderClientError/settingsUnreadable`` when the choice or the key can't be read, or `CancellationError`.
    private func endpoint() async throws -> Endpoint {
        let endpoint = try await providers.loadedConnection()
        if case .custom = endpoint, network != .mainnet { throw ProviderClientError.unsupportedNetwork }
        return endpoint
    }

    /// Creates the client for an endpoint on a network.
    ///
    /// - Parameters:
    ///   - endpoint: The provider and what it needs to accept requests.
    ///   - network: The network that receives the client's requests.
    /// - Returns: The provider's client, or `nil` for a custom URL that isn't HTTPS with a host.
    static func client(for endpoint: Endpoint,
                       on network: Network) -> Client? {
        switch endpoint {
        case .solana: Solana(network: network)
        case .helius(let key): HeliusRPC(apiKey: key, network: network)
        case .custom(let url): Solana(endpoint: url, network: network)
        }
    }

    /// Keeps the client for the most recent endpoint and replaces it when the endpoint changes.
    private actor Clients {
        private let network: Network
        private let make: @Sendable (Endpoint, Network) -> Client?
        private var current: (endpoint: Endpoint, client: Client)?

        /// Creates an empty cache.
        ///
        /// - Parameters:
        ///   - network: The network that every created client serves.
        ///   - make: A function that creates the client for an endpoint on a network.
        init(network: Network, make: @escaping @Sendable (Endpoint, Network) -> Client?) {
            self.network = network
            self.make = make
        }

        /// Returns the kept client for this endpoint, or creates one for a new endpoint.
        ///
        /// - Parameter endpoint: The endpoint for the request.
        /// - Returns: A client that sends requests to this endpoint.
        /// - Throws: ``ProviderClientError/unusableEndpoint`` for a saved endpoint that can't be used.
        func client(for endpoint: Endpoint) throws -> Client {
            if let current, current.endpoint == endpoint { return current.client }
            guard let client = make(endpoint, network) else { throw ProviderClientError.unusableEndpoint }
            current = (endpoint, client)
            return client
        }
    }
}
