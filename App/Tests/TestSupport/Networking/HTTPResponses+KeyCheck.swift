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

    /// Creates the production saved-key client with these fixtures in place of the network.
    /// - Parameter providerKey: The test's isolated key storage.
    /// - Returns: A client whose Helius requests never leave the process.
    nonisolated func heliusClient(providerKey: any ValueStoring<String>) -> HeliusClient {
        HeliusClient(providerKey: providerKey) { HeliusRPC(apiKey: $0, network: .mainnet, transport: self) }
    }
}
