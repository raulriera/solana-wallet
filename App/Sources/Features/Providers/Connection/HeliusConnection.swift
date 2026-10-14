import Foundation
import RPC

/// Connects the app to Helius, its only DAS provider, with a user-supplied mainnet key.
nonisolated struct HeliusConnection: ProviderConnecting {
    typealias EntryError = ProviderConnectionError

    private let providerKey: any ValueStoring<String>
    private let revisions: ProviderRevisions
    private let client: @Sendable (String) -> any RPC

    /// Creates a connection that checks keys against Helius mainnet.
    /// - Parameters:
    ///   - providerKey: Device-only storage for the accepted key.
    ///   - revisions: Tell every window when a saved key applies.
    ///   - client: Creates the Helius client for a candidate key.
    init(providerKey: any ValueStoring<String>, revisions: ProviderRevisions,
         client: @escaping @Sendable (String) -> any RPC = { HeliusRPC(apiKey: $0, network: .mainnet) }) {
        self.providerKey = providerKey
        self.revisions = revisions
        self.client = client
    }

    /// Makes one DAS request with the key, saves the key only after Helius accepts it, and tells every window.
    /// - Parameter key: The key, without surrounding whitespace.
    /// - Throws: ``ProviderConnectionError`` or `CancellationError`, never containing the key.
    func connect(_ key: String) async throws {
        guard !key.isEmpty else { throw ProviderConnectionError.invalidKey }
        do {
            _ = try await client(key).send(GetAsset(id: Self.checkedAccount))
        } catch {
            try Task.checkCancellation()
            let connectionError: ProviderConnectionError = switch error as? RPCError {
            case .http(statusCode: 401, retryAfter: _)?, .http(statusCode: 403, retryAfter: _)?: .invalidKey
            case let error? where error.isRateLimited: .rateLimited
            default: .unavailable
            }
            throw connectionError
        }
        try Task.checkCancellation()
        do {
            try await providerKey.save(key)
        } catch {
            try Task.checkCancellation()
            throw ProviderConnectionError.storageFailed
        }
        // Both in one main-actor turn, so no window sees the saved key in its list without the new connection.
        await MainActor.run {
            revisions.settings.advance()
            revisions.connection.advance()
        }
    }
}
