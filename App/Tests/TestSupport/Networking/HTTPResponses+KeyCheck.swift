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
    ///   - providerKey: The test's isolated key storage.
    ///   - responses: The fixtures that answer a given key.
    /// - Returns: A connection whose Helius client never leaves the process.
    nonisolated static func connection(providerKey: any ValueStoring<String>,
                                       responding responses: @escaping @Sendable (String) -> HTTPResponses) -> HeliusConnection {
        HeliusConnection(providerKey: providerKey) { HeliusRPC(apiKey: $0, network: .mainnet, transport: responses($0)) }
    }

    /// Creates the production connection with these fixtures in place of the network.
    /// - Parameter providerKey: The test's isolated key storage.
    /// - Returns: A connection whose Helius client never leaves the process.
    nonisolated func connection(providerKey: any ValueStoring<String>) -> HeliusConnection {
        Self.connection(providerKey: providerKey) { _ in self }
    }

    /// Creates the client that production uses for an endpoint, with these fixtures in place of the network.
    /// - Parameter endpoint: The provider and what it needs to accept requests.
    /// - Returns: The provider's client, or `nil` for a custom URL that isn't HTTPS with a host.
    nonisolated func client(for endpoint: ProviderClient.Endpoint) -> (any RPC & AccountChangeProviding)? {
        switch endpoint {
        case .solana: Solana(network: .mainnet, transport: self)
        case .helius(let key): HeliusRPC(apiKey: key, network: .mainnet, transport: self)
        case .custom(let url): Solana(endpoint: url, network: .mainnet, transport: self)
        }
    }

    /// Creates the production selected-provider client with these fixtures in place of the network.
    /// - Parameters:
    ///   - settings: The test's provider choice.
    ///   - providerKey: The test's isolated key storage.
    /// - Returns: A client whose requests never leave the process.
    nonisolated func providerClient(settings: any ValueStoring<ProviderSettings>,
                                    providerKey: any ValueStoring<String>) -> ProviderClient {
        ProviderClient(settings: settings, providerKey: providerKey) { self.client(for: $0) }
    }
}
