import Foundation
import RPC

/// Sends one network's requests through the RPC provider selected on this device.
///
/// Each request and subscription reads the saved choice, and Helius's saved key, so a change made in any
/// window applies to the next request. Solana's public RPC and Helius serve each network at its own host; Helius
/// uses the same key on each network. A custom RPC serves mainnet only; on another network it fails instead of
/// using another provider. A capability the selected provider lacks gives its empty result: only Helius has logo
/// copies. Only Helius reads private notes; another provider's private-note reads throw
/// ``ProviderClientError/privateNotesUnavailable``. The client for the latest provider is kept to reuse its connections.
nonisolated struct ProviderClient: RPC, AccountChangeProviding, LogoProviding, PrivateNoteProviding {
    /// Where requests go, with what the provider needs to accept them.
    nonisolated enum Endpoint: Hashable, Sendable {
        /// Solana's public RPC.
        case solana
        /// Helius, with the saved API key.
        case helius(key: String)
        /// A custom HTTPS RPC.
        case custom(URL)
    }

    /// The client for an endpoint on a network, or `nil` when the endpoint can't be used.
    typealias ClientFactory = @Sendable (Endpoint, Network) -> (any RPC & AccountChangeProviding & SignatureEventProviding)?

    /// The network that receives every request and subscription.
    let network: Network
    private let settings: any ValueStoring<ProviderSettings>
    private let providerKey: any ValueStoring<String>
    private let clients: Clients

    /// Creates a client that reads the selected provider from device storage before every request.
    /// - Parameters:
    ///   - network: The network that receives every request and subscription.
    ///   - settings: Device-only storage for the provider choice.
    ///   - providerKey: Device-only storage for Helius's accepted key.
    ///   - client: Creates the client for an endpoint on a network.
    init(network: Network, settings: any ValueStoring<ProviderSettings>, providerKey: any ValueStoring<String>,
         client: @escaping ClientFactory = Self.client(for:on:)) {
        self.network = network
        self.settings = settings
        self.providerKey = providerKey
        clients = Clients(network: network, make: client)
    }

    /// Sends one request to the selected provider, without retrying it.
    /// - Parameter request: The RPC method and its parameters.
    /// - Returns: The validated and decoded response.
    /// - Throws: ``ProviderClientError`` for a missing or rejected Helius key or a custom RPC on another network,
    ///   a storage error, any other `RPCError`, or `CancellationError`.
    func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        try await perform { try await $0.send(request) }
    }

    /// Observes finalized changes to each account through the selected provider.
    /// - Parameter addresses: The accounts to watch; a repeated address is watched once.
    /// - Returns: Increasing finalized change slots after all subscriptions are acknowledged.
    /// - Throws: ``ProviderClientError`` for a missing or rejected Helius key or a custom RPC on another network,
    ///   a storage error, or another sanitized subscription, transport, timeout, or cancellation error.
    func changedSlots(for addresses: [String]) async throws -> AsyncThrowingStream<UInt64, any Error> {
        try await perform { try await $0.changedSlots(for: addresses) }
    }

    /// Looks up the selected provider's copies of token logos.
    /// - Parameter mints: Mint addresses; duplicates are ignored.
    /// - Returns: Logo URLs on the provider's CDN, keyed by mint address, or none, without a request,
    ///   when the provider has no logo copies.
    /// - Throws: ``ProviderClientError`` for a missing or rejected Helius key or a custom RPC on another network,
    ///   a storage error, any other `RPCError`, or `CancellationError`.
    func logos(for mints: [String]) async throws -> [String: URL] {
        try await perform { client in
            guard let client = client as? any LogoProviding else { return [:] }
            return try await client.logos(for: mints)
        }
    }

    /// Reads the selected provider's private-note transactions tagged with any of the view tags, after a position.
    /// - Parameters:
    ///   - tags: 32-byte view tags, such as an account's Ed25519 public key.
    ///   - position: The position from an earlier read of the same tags, or `nil` to read from the start.
    /// - Returns: The provider's transactions, tree, and next position.
    /// - Throws: ``ProviderClientError/privateNotesUnavailable`` when the selected provider doesn't read private notes,
    ///   another ``ProviderClientError``, a storage error, a `PrivateNoteError`, any other `RPCError`, or
    ///   `CancellationError`.
    func shieldedTransactions(taggedWith tags: [[UInt8]], after position: NoteSyncPosition?) async throws
        -> ShieldedTransactionBatch {
        try await performPrivateNotes { try await $0.shieldedTransactions(taggedWith: tags, after: position) }
    }

    /// Reads the selected provider's transactions that spent any of the nullifiers.
    /// - Parameter nullifiers: 32-byte nullifiers.
    /// - Returns: Each spending transaction once, in slot and signature order.
    /// - Throws: ``ProviderClientError/privateNotesUnavailable`` when the selected provider doesn't read private notes,
    ///   another ``ProviderClientError``, a storage error, a `PrivateNoteError`, any other `RPCError`, or
    ///   `CancellationError`.
    func shieldedTransactions(spending nullifiers: [[UInt8]]) async throws -> [ShieldedTransaction] {
        try await performPrivateNotes { try await $0.shieldedTransactions(spending: nullifiers) }
    }

    /// Runs a private-note read on the selected provider's client.
    /// - Parameter operation: The read to send to the provider.
    /// - Returns: The read's result.
    /// - Throws: ``ProviderClientError/privateNotesUnavailable`` when the selected provider doesn't read private notes,
    ///   or the error of ``perform(_:)``.
    private func performPrivateNotes<Value: Sendable>(
        _ operation: (any PrivateNoteProviding) async throws -> Value
    ) async throws -> Value {
        try await perform { client in
            guard let client = client as? any PrivateNoteProviding else { throw ProviderClientError.privateNotesUnavailable }
            return try await operation(client)
        }
    }

    /// Runs an operation on the selected provider's client.
    /// - Parameter operation: The work to send to the provider.
    /// - Returns: The operation's result.
    /// - Throws: The operation's error, with Helius's key rejections as ``ProviderClientError/invalidKey``.
    private func perform<Value: Sendable>(
        _ operation: (any RPC & AccountChangeProviding) async throws -> Value
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

    /// Reads the saved choice and, for Helius, its key.
    /// - Returns: The endpoint that receives the next request.
    /// - Throws: ``ProviderClientError/missingKey`` when Helius is selected without a key,
    ///   ``ProviderClientError/unsupportedNetwork`` when a custom RPC is selected off mainnet, or a storage or
    ///   cancellation error.
    private func endpoint() async throws -> Endpoint {
        switch (try await settings.load() ?? ProviderSettings()).selection {
        case .solana:
            return .solana
        case .custom(let url):
            guard network == .mainnet else { throw ProviderClientError.unsupportedNetwork }
            return .custom(url)
        case .helius:
            return .helius(key: try await Self.heliusKey(in: providerKey))
        }
    }

    /// Reads Helius's saved key.
    /// - Parameter store: Device-only storage for Helius's accepted key.
    /// - Returns: The saved key.
    /// - Throws: ``ProviderClientError/missingKey`` when no key is saved, or a storage or cancellation error; a
    ///   cancelled read is never reported as a missing key.
    static func heliusKey(in store: any ValueStoring<String>) async throws -> String {
        guard let key = try await store.load() else {
            try Task.checkCancellation()
            throw ProviderClientError.missingKey
        }
        return key
    }

    /// Creates the production client for an endpoint on a network.
    /// - Parameters:
    ///   - endpoint: The provider and what it needs to accept requests.
    ///   - network: The network that receives the client's requests; a custom URL must serve it.
    /// - Returns: The provider's client, or `nil` for a custom URL that isn't HTTPS with a host.
    static func client(for endpoint: Endpoint,
                       on network: Network) -> (any RPC & AccountChangeProviding & SignatureEventProviding)? {
        switch endpoint {
        case .solana: Solana(network: network)
        case .helius(let key): HeliusRPC(apiKey: key, network: network)
        case .custom(let url): Solana(endpoint: url, network: network)
        }
    }

    /// Keeps the client for the most recent endpoint and replaces it when the endpoint changes.
    private actor Clients {
        private let network: Network
        private let make: ClientFactory
        private var current: (endpoint: Endpoint, client: any RPC & AccountChangeProviding)?

        /// Creates an empty cache.
        /// - Parameters:
        ///   - network: The network that every created client serves.
        ///   - make: Creates the client for an endpoint on a network.
        init(network: Network, make: @escaping ClientFactory) {
            self.network = network
            self.make = make
        }

        /// Returns the kept client for this endpoint, or creates one for a new endpoint.
        /// - Parameter endpoint: The endpoint read from storage for this request.
        /// - Returns: A client that sends requests to this endpoint.
        /// - Throws: ``ProviderClientError/unusableEndpoint`` for a saved endpoint that can't be used.
        func client(for endpoint: Endpoint) throws -> any RPC & AccountChangeProviding {
            if let current, current.endpoint == endpoint { return current.client }
            guard let client = make(endpoint, network) else { throw ProviderClientError.unusableEndpoint }
            current = (endpoint, client)
            return client
        }
    }
}
