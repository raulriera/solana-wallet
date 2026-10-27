import Foundation
@testable import RPC
@testable import widgets

extension HTTPResponses {
    /// The native SOL mint, the asset that key-check fixtures answer for.
    nonisolated static let keyCheckAsset = "So11111111111111111111111111111111111111112"

    /// Answers the provider's key check with a minimal DAS asset accepted by the real response decoder.
    /// - Parameters:
    ///   - error: An optional HTTP or transport failure.
    ///   - gate: An optional suspension before returning the HTTP response.
    /// - Returns: A request-recording transport for provider key checks.
    static func keyCheck(error: RPCError? = nil, gate: Suspension? = nil) -> HTTPResponses {
        let asset = #"{"id":"\#(keyCheckAsset)","interface":"FungibleToken","mutable":false}"#
        return HTTPResponses(["getAsset": [asset]], error: error, gate: gate)
    }

    /// Creates the production connection, answering each checked key with its own fixtures.
    /// - Parameters:
    ///   - providers: The test's provider settings, which keep the accepted key.
    ///   - responses: The fixtures that answer a given key.
    /// - Returns: A connection whose Helius client never leaves the process.
    nonisolated static func connection(providers: ProviderStore,
                                       responding responses: @escaping @Sendable (String) -> HTTPResponses) -> HeliusConnection {
        HeliusConnection(providers: providers) {
            HeliusRPC(apiKey: $0, network: .mainnet, transport: responses($0))
        }
    }

    /// Creates the production connection with these fixtures in place of the network.
    /// - Parameter providers: The test's provider settings, which keep the accepted key.
    /// - Returns: A connection whose Helius client never leaves the process.
    nonisolated func connection(providers: ProviderStore) -> HeliusConnection {
        Self.connection(providers: providers) { _ in self }
    }

    /// Creates the client that production uses for an endpoint on a Solana network, with these fixtures in place of
    /// the internet.
    /// - Parameters:
    ///   - endpoint: The provider and what it needs to accept requests.
    ///   - network: The Solana network that receives the client's requests.
    ///   - socket: Opens each subscription connection; by default, a local socket that acknowledges each subscription.
    /// - Returns: The provider's client, or `nil` for a custom URL that isn't HTTPS with a host.
    nonisolated func client(for endpoint: ProviderClient.Endpoint, on network: Network,
                            socket: @escaping @Sendable (URL) -> any WebSocketConnection = { _ in SocketFixture() })
        -> (any RPC & AccountChangeProviding & SignatureEventProviding)? {
        switch endpoint {
        case .solana: Solana(network: network, transport: self, socket: socket)
        case .helius(let key): HeliusRPC(apiKey: key, network: network, transport: self, socket: socket)
        case .custom(let url): Solana(endpoint: url, network: network, transport: self, socket: socket)
        }
    }

    /// Creates the production selected-provider client with these fixtures in place of the internet.
    /// - Parameters:
    ///   - network: The Solana network that receives every request; mainnet by default.
    ///   - providers: The test's provider choice and key.
    /// - Returns: A client whose requests never leave the process.
    nonisolated func providerClient(network: Network = .mainnet, providers: ProviderStore) -> ProviderClient {
        ProviderClient(network: network, providers: providers) { self.client(for: $0, on: $1) }
    }
}
