import Foundation
import RPC

/// Connects the app to Helius, its only DAS provider, with a user-supplied key.
nonisolated struct HeliusConnection: ProviderConnecting {
    typealias EntryError = ProviderConnectionError

    private let providers: ProviderStore
    private let client: @Sendable (String) -> any RPC

    /// Creates a connection that checks keys against Helius mainnet.
    /// - Parameters:
    ///   - providers: The provider settings that every window shares, which keep the accepted key.
    ///   - client: Creates the Helius client for a candidate key.
    init(providers: ProviderStore,
         client: @escaping @Sendable (String) -> any RPC = { HeliusRPC(apiKey: $0, network: .mainnet) }) {
        self.providers = providers
        self.client = client
    }

    /// Makes one DAS request with the key, and saves the key for every window only after Helius accepts it.
    /// - Parameter key: The key, without surrounding whitespace.
    /// - Throws: ``ProviderConnectionError`` or `CancellationError`, never containing the key.
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
