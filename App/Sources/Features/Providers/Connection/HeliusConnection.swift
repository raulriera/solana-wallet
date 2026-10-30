import Foundation
import RPC

/// Checks a Helius API key, then saves it.
nonisolated struct HeliusConnection: ProviderConnecting {
    typealias EntryError = ProviderConnectionError

    private let providers: ProviderStore
    private let client: @Sendable (String) -> any RPC

    /// Creates a connection that checks keys against Helius mainnet.
    ///
    /// - Parameters:
    ///   - providers: The provider settings that save the accepted key.
    ///   - client: A function that creates the Helius client for a candidate key.
    init(providers: ProviderStore,
         client: @escaping @Sendable (String) -> any RPC = { HeliusRPC(apiKey: $0, network: .mainnet) }) {
        self.providers = providers
        self.client = client
    }

    func connect(_ key: String) async throws {
        guard !key.isEmpty else { throw ProviderConnectionError.invalidKey }
        do {
            _ = try await client(key).send(GetAsset(id: Self.checkedAccount))
        } catch {
            try Task.checkCancellation()
            let connectionError: ProviderConnectionError = switch error as? RPCError {
            case let error? where error.rejectsKey: .invalidKey
            case let error? where error.isRateLimited: .rateLimited
            default: .unavailable
            }
            throw connectionError
        }
        try Task.checkCancellation()
        do {
            try await providers.save(key: key)
        } catch {
            try Task.checkCancellation()
            throw ProviderConnectionError.storageFailed
        }
    }
}
