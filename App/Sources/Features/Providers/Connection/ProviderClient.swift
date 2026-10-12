import Foundation
import RPC

/// Sends mainnet requests through the RPC provider selected on this device.
///
/// Each request and subscription reads the saved choice, and Helius's saved key, so a change made in any
/// window applies to the next request. A capability the selected provider lacks gives its empty result:
/// only Helius has logo copies. The client for the latest provider is kept to reuse its connections.
nonisolated struct ProviderClient: RPC, AccountChangeProviding, LogoProviding {
    /// Where requests go, with what the provider needs to accept them.
    nonisolated enum Endpoint: Hashable, Sendable {
        /// Solana's public mainnet RPC.
        case solana
        /// Helius, with the saved API key.
        case helius(key: String)
        /// A custom HTTPS RPC.
        case custom(URL)
    }

    /// The client for an endpoint, or `nil` when the endpoint can't be used.
    typealias ClientFactory = @Sendable (Endpoint) -> (any RPC & AccountChangeProviding)?

    let network = Network.mainnet
    private let settings: any ValueStoring<ProviderSettings>
    private let providerKey: any ValueStoring<String>
    private let clients: Clients

    /// Creates a client that reads the selected provider from device storage before every request.
    /// - Parameters:
    ///   - settings: Device-only storage for the provider choice.
    ///   - providerKey: Device-only storage for Helius's accepted key.
    ///   - client: Creates the mainnet client for an endpoint.
    init(settings: any ValueStoring<ProviderSettings>, providerKey: any ValueStoring<String>,
         client: @escaping ClientFactory = Self.mainnetClient(for:)) {
        self.settings = settings
        self.providerKey = providerKey
        clients = Clients(make: client)
    }

    /// Sends one request to the selected provider, without retrying it.
    /// - Parameter request: The RPC method and its parameters.
    /// - Returns: The validated and decoded response.
    /// - Throws: ``ProviderClientError`` for a missing or rejected Helius key, a storage error, any other
    ///   `RPCError`, or `CancellationError`.
    func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        try await perform { try await $0.send(request) }
    }

    /// Observes confirmed changes to each account through the selected provider.
    /// - Parameter addresses: The accounts to watch; a repeated address is watched once.
    /// - Returns: Increasing confirmed change slots after all subscriptions are acknowledged.
    /// - Throws: ``ProviderClientError`` for a missing or rejected Helius key, a storage error, or another
    ///   sanitized subscription, transport, timeout, or cancellation error.
    func changedSlots(for addresses: [String]) async throws -> AsyncThrowingStream<UInt64, any Error> {
        try await perform { try await $0.changedSlots(for: addresses) }
    }

    /// Looks up the selected provider's copies of token logos.
    /// - Parameter mints: Mint addresses; duplicates are ignored.
    /// - Returns: Logo URLs on the provider's CDN, keyed by mint address, or none, without a request,
    ///   when the provider has no logo copies.
    /// - Throws: ``ProviderClientError`` for a missing or rejected Helius key, a storage error, any other
    ///   `RPCError`, or `CancellationError`.
    func logos(for mints: [String]) async throws -> [String: URL] {
        try await perform { client in
            guard let client = client as? any LogoProviding else { return [:] }
            return try await client.logos(for: mints)
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
            guard case .helius = endpoint, let keyError = Self.keyError(for: error) else { throw error }
            throw keyError
        }
    }

    /// Reads the saved choice and, for Helius, its key.
    /// - Returns: The endpoint that receives the next request.
    /// - Throws: ``ProviderClientError/missingKey`` when Helius is selected without a key, or a storage
    ///   or cancellation error.
    private func endpoint() async throws -> Endpoint {
        switch (try await settings.load() ?? ProviderSettings()).selection {
        case .solana:
            return .solana
        case .custom(let url):
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

    /// Identifies Helius rejecting the key, so other responses can't be mistaken for it.
    /// - Parameter error: An error from a Helius request or subscription.
    /// - Returns: ``ProviderClientError/invalidKey`` for HTTP 401 or 403, otherwise `nil`.
    private static func keyError(for error: any Error) -> ProviderClientError? {
        switch error {
        case RPCError.http(statusCode: 401, retryAfter: _), RPCError.http(statusCode: 403, retryAfter: _): .invalidKey
        default: nil
        }
    }

    /// Creates the production mainnet client for an endpoint.
    /// - Parameter endpoint: The provider and what it needs to accept requests.
    /// - Returns: The provider's client, or `nil` for a custom URL that isn't HTTPS with a host.
    static func mainnetClient(for endpoint: Endpoint) -> (any RPC & AccountChangeProviding)? {
        switch endpoint {
        case .solana: Solana(network: .mainnet)
        case .helius(let key): HeliusRPC(apiKey: key, network: .mainnet)
        case .custom(let url): Solana(endpoint: url, network: .mainnet)
        }
    }

    /// Keeps the client for the most recent endpoint and replaces it when the endpoint changes.
    private actor Clients {
        private let make: ClientFactory
        private var current: (endpoint: Endpoint, client: any RPC & AccountChangeProviding)?

        /// Creates an empty cache.
        /// - Parameter make: Creates the client for an endpoint.
        init(make: @escaping ClientFactory) {
            self.make = make
        }

        /// Returns the kept client for this endpoint, or creates one for a new endpoint.
        /// - Parameter endpoint: The endpoint read from storage for this request.
        /// - Returns: A client that sends requests to this endpoint.
        /// - Throws: ``ProviderClientError/unusableEndpoint`` for a saved endpoint that can't be used.
        func client(for endpoint: Endpoint) throws -> any RPC & AccountChangeProviding {
            if let current, current.endpoint == endpoint { return current.client }
            guard let client = make(endpoint) else { throw ProviderClientError.unusableEndpoint }
            current = (endpoint, client)
            return client
        }
    }
}
