@testable import RPC
@testable import widgets

extension HTTPResponses {
    /// The native SOL mint, the asset that key-check fixtures answer for.
    nonisolated static let keyCheckAsset = "So11111111111111111111111111111111111111112"

    /// Answers the provider's key check with a minimal DAS asset accepted by the real response decoder.
    /// - Parameters:
    ///   - failure: An optional HTTP or transport failure.
    ///   - gate: An optional suspension before returning the HTTP response.
    /// - Returns: A request-recording transport for provider key checks.
    static func keyCheck(failure: RPCError? = nil, gate: Suspension? = nil) -> HTTPResponses {
        let asset = #"{"id":"\#(keyCheckAsset)","interface":"FungibleToken","mutable":false}"#
        return HTTPResponses(["getAsset": [asset]], failure: failure, gate: gate)
    }

    /// Creates the production connection, answering each checked key with its own fixtures.
    /// - Parameters:
    ///   - keys: The test's isolated key storage.
    ///   - responses: The fixtures that answer a given key.
    /// - Returns: A connection whose Helius client never leaves the process.
    nonisolated static func connection(keys: any ProviderKeyStoring,
                                       responding responses: @escaping @Sendable (String) -> HTTPResponses) -> HeliusConnection {
        HeliusConnection(keys: keys) { HeliusRPC(apiKey: $0, network: .mainnet, transport: responses($0)) }
    }

    /// Creates the production connection with these fixtures in place of the network.
    /// - Parameter keys: The test's isolated key storage.
    /// - Returns: A connection whose Helius client never leaves the process.
    nonisolated func connection(keys: any ProviderKeyStoring) -> HeliusConnection {
        Self.connection(keys: keys) { _ in self }
    }

    /// Creates the production saved-key client with these fixtures in place of the network.
    /// - Parameter keys: The test's isolated key storage.
    /// - Returns: A client whose Helius requests never leave the process.
    nonisolated func heliusClient(keys: any ProviderKeyStoring) -> HeliusClient {
        HeliusClient(keys: keys) { HeliusRPC(apiKey: $0, network: .mainnet, transport: self) }
    }
}
