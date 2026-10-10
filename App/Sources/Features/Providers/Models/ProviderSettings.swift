import Foundation

/// The RPC provider that every window uses and the custom RPCs a person added, saved on this device.
nonisolated struct ProviderSettings: Codable, Equatable, Sendable {
    /// An RPC provider. Saved case names are permanent.
    nonisolated enum Provider: Codable, Hashable, Sendable {
        /// Solana's public mainnet RPC, which needs no key.
        case solana
        /// Helius, with the API key saved on this device.
        case helius
        /// A custom HTTPS RPC, identified by its URL, which can contain a key.
        case custom(URL)
    }

    /// The provider in use: Helius until a person chooses another, as before this setting existed.
    var selection = Provider.helius
    /// Custom RPC URLs, in the order they were added.
    var customRPCs: [URL] = []

    /// Chooses the provider that every window uses next.
    /// - Parameter provider: The provider to use.
    /// - Returns: Whether the choice changed; choosing the provider in use changes nothing.
    mutating func select(_ provider: Provider) -> Bool {
        guard provider != selection else { return false }
        selection = provider
        return true
    }
}
