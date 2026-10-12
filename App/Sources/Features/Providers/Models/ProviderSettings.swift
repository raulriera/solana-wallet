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

        /// The provider's name as people see it; a custom RPC shows only its host, never a key in its URL.
        var name: LocalizedStringResource {
            switch self {
            case .solana: "Solana"
            case .helius: "Helius"
            case .custom(let url):
                LocalizedStringResource("\(url.host() ?? "")", comment: "A custom RPC's host, shown exactly as entered.")
            }
        }

        /// Whether the provider has details to show: Helius's key, or a custom RPC's URL.
        var hasDetails: Bool { self != .solana }
    }

    /// The provider in use: Helius until a person chooses another, as before this setting existed.
    var selection = Provider.helius
    /// Custom RPC URLs, in the order they were added.
    var customRPCs: [URL] = []

    /// Chooses the provider that every window uses next.
    /// - Parameter provider: The provider to use; a custom RPC must already be in the list.
    /// - Returns: Whether the choice changed; choosing the provider in use, or an unlisted custom RPC, changes nothing.
    mutating func select(_ provider: Provider) -> Bool {
        if case .custom(let url) = provider, !customRPCs.contains(url) { return false }
        guard provider != selection else { return false }
        selection = provider
        return true
    }

    /// Adds a custom RPC, if it's new, and chooses it.
    /// - Parameter url: The checked RPC URL.
    /// - Returns: Whether the settings changed; adding the RPC in use changes nothing.
    mutating func add(_ url: URL) -> Bool {
        let isNew = !customRPCs.contains(url)
        if isNew { customRPCs.append(url) }
        return select(.custom(url)) || isNew
    }

    /// Removes a custom RPC; removing the one in use chooses Solana.
    /// - Parameter url: The RPC URL to remove.
    /// - Returns: Whether the provider in use changed.
    mutating func remove(_ url: URL) -> Bool {
        customRPCs.removeAll { $0 == url }
        return selection == .custom(url) && select(.solana)
    }
}
