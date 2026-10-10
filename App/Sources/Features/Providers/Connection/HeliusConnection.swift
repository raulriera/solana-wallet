import Foundation
import RPC

/// Connects the app to Helius, its only DAS provider, with a user-supplied mainnet key.
nonisolated struct HeliusConnection: ProviderConnecting {
    /// The native SOL mint, whose metadata any Helius key can read.
    private static let nativeMint = "So11111111111111111111111111111111111111112"

    private let providerKey: any ValueStoring<String>
    private let client: @Sendable (String) -> any RPC

    /// Creates a connection that checks keys against Helius mainnet.
    /// - Parameters:
    ///   - providerKey: Device-only storage for the accepted key.
    ///   - client: Creates the Helius client for a candidate key.
    init(providerKey: any ValueStoring<String>,
         client: @escaping @Sendable (String) -> any RPC = { HeliusRPC(apiKey: $0, network: .mainnet) }) {
        self.providerKey = providerKey
        self.client = client
    }

    /// Makes one DAS request with the key and saves the key only after Helius accepts it.
    /// - Parameter apiKey: The key as entered; surrounding whitespace is ignored.
    /// - Throws: ``ProviderConnectionError`` or `CancellationError`, never containing the key.
    func connect(apiKey: String) async throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ProviderConnectionError.invalidKey }
        do {
            _ = try await client(key).send(GetAsset(id: Self.nativeMint))
        } catch {
            try Task.checkCancellation()
            let connectionError: ProviderConnectionError = switch error as? RPCError {
            case .http(statusCode: 401, retryAfter: _)?, .http(statusCode: 403, retryAfter: _)?: .invalidKey
            case .http(statusCode: 429, retryAfter: _)?: .rateLimited
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
    }
}
