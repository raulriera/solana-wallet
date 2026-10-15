import Foundation

/// The RPC provider that every window uses and the custom RPCs a person added, saved on this device.
nonisolated struct ProviderSettings: Codable, Equatable, Sendable {
    /// An RPC provider.
    nonisolated enum Provider: Codable, Hashable, Sendable {
        /// Solana's public RPC, which needs no key.
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

    /// The provider in use: Solana's public RPC until a person chooses another.
    var selection = Provider.solana
    /// Custom RPC URLs, in the order they were added.
    var customRPCs: [URL] = []

    /// Chooses the provider that every window uses next; an unlisted custom RPC changes nothing.
    /// - Parameter provider: The provider to use; a custom RPC must already be in the list.
    mutating func select(_ provider: Provider) {
        if case .custom(let url) = provider, !customRPCs.contains(url) { return }
        selection = provider
    }

    /// Adds a custom RPC, if it's new, and chooses it.
    /// - Parameter url: The checked RPC URL.
    mutating func add(_ url: URL) {
        if !customRPCs.contains(url) { customRPCs.append(url) }
        select(.custom(url))
    }

    /// Removes a custom RPC; removing the one in use chooses Solana.
    /// - Parameter url: The RPC URL to remove.
    mutating func remove(_ url: URL) {
        customRPCs.removeAll { $0 == url }
        if selection == .custom(url) { selection = .solana }
    }
}
