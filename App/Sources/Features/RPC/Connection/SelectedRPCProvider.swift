import Foundation
import RPC

/// Sends one network's requests, private-note reads, and proofs through the selected RPC provider.
nonisolated struct SelectedRPCProvider: RPC, AccountChangeProviding, SignatureEventProviding, LogoProviding,
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
    private let rpcStore: RPCStore
    private let clients: ClientCache<Endpoint, Client>

    /// Creates a client that reads the selected provider before every request.
    ///
    /// - Parameters:
    ///   - network: The network that receives every request and subscription.
    ///   - rpcStore: The provider settings to read.
    ///   - client: A function that creates the client for an endpoint on a network.
    init(network: Network, rpcStore: RPCStore,
         client: @escaping @Sendable (Endpoint, Network) -> Client? = Self.client(for:on:)) {
        self.network = network
        self.rpcStore = rpcStore
        clients = ClientCache { endpoint in
            guard let made = client(endpoint, network) else { throw RPCProviderError.unusableEndpoint }
            return made
        }
    }

    var capabilities: Capabilities {
        get async throws {
            guard let endpoint = try await endpoint() else { return [] }
            return try await clients.client(for: endpoint).capabilities
        }
    }

    func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        try await perform { try await $0.send(request) }
    }

    func logos(for mints: [String]) async throws -> [String: URL] {
        try await perform { try await ($0 as? any LogoProviding)?.logos(for: mints) ?? [:] }
    }

    func changedSlots(for addresses: [String]) async throws -> AsyncThrowingStream<UInt64, any Error> {
        try await perform { try await $0.changedSlots(for: addresses) }
    }

    func events(for signature: String) async throws -> AsyncThrowingStream<SignatureEvent, any Error> {
        try await perform { try await $0.events(for: signature) }
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

    /// Runs a private-note read or proof on the selected provider's client.
    ///
    /// - Parameter operation: The read or proof.
    /// - Returns: The operation's result.
    /// - Throws: ``RPCProviderError/unsupportedNetwork`` for a provider without private notes and proofs, or the
    ///   error of ``perform(_:)``.
    private func performRings<Value: Sendable>(
        _ operation: (any PrivateNoteProviding & ProofProviding) async throws -> Value
    ) async throws -> Value {
        try await perform { client in
            guard let client = client as? any PrivateNoteProviding & ProofProviding else {
                throw RPCProviderError.unsupportedNetwork
            }
            return try await operation(client)
        }
    }

    /// Runs an operation on the selected provider's client.
    ///
    /// - Parameter operation: The work to send to the provider.
    /// - Returns: The operation's result.
    /// - Throws: ``RPCProviderError/unsupportedNetwork`` when a custom RPC is selected off mainnet, the error of
    ///   ``endpoint()``, or the operation's error, with Helius's key rejections as ``RPCProviderError/invalidKey``.
    private func perform<Value: Sendable>(
        _ operation: (Client) async throws -> Value
    ) async throws -> Value {
        guard let endpoint = try await endpoint() else { throw RPCProviderError.unsupportedNetwork }
        let client = try await clients.client(for: endpoint)
        do {
            return try await operation(client)
        } catch {
            guard case .helius = endpoint, (error as? RPCError)?.rejectsKey == true else { throw error }
            throw RPCProviderError.invalidKey
        }
    }

    /// Reads the selected provider and, for Helius, its key.
    ///
    /// - Returns: The endpoint that receives the next request, or `nil` when a custom RPC is selected off mainnet.
    /// - Throws: ``RPCProviderError/missingKey`` when Helius is selected without a key,
    ///   ``RPCProviderError/settingsUnreadable`` when the choice or the key can't be read, or `CancellationError`.
    private func endpoint() async throws -> Endpoint? {
        let endpoint = try await rpcStore.loadedConnection()
        if case .custom = endpoint, network != .mainnet { return nil }
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
        case .solana: SolanaRPC(network: network)
        case .helius(let key): HeliusRPC(apiKey: key, network: network)
        case .custom(let url): SolanaRPC(endpoint: url, network: network)
        }
    }
}
