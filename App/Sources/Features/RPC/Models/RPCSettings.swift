import Foundation

/// The RPC provider in use and the custom RPCs a person added.
nonisolated struct RPCSettings: Codable, Equatable, Sendable {
    /// An RPC provider.
    nonisolated enum Provider: Codable, Hashable, Sendable {
        /// Solana's public RPC.
        case solana
        case helius
        case custom(URL)

        /// The provider's name, or a custom RPC's host.
        var name: LocalizedStringResource {
            switch self {
            case .solana: "Solana"
            case .helius: "Helius"
            case .custom(let url):
                LocalizedStringResource("\(url.host() ?? "")", comment: "A custom RPC's host, shown exactly as entered.")
            }
        }

        var hasDetails: Bool { self != .solana }
    }

    /// The provider in use.
    var selection = Provider.solana
    /// The custom RPC URLs in the order they were added.
    var customRPCs: [URL] = []

    /// Chooses the provider in use.
    ///
    /// - Parameter provider: The provider to use; a custom RPC must already be in the list.
    mutating func select(_ provider: Provider) {
        if case .custom(let url) = provider, !customRPCs.contains(url) { return }
        selection = provider
    }

    /// Adds a custom RPC, if it's new, and chooses it.
    ///
    /// - Parameter url: The checked RPC URL.
    mutating func add(_ url: URL) {
        if !customRPCs.contains(url) { customRPCs.append(url) }
        select(.custom(url))
    }

    /// Removes a custom RPC, choosing Solana if it was in use.
    ///
    /// - Parameter url: The RPC URL to remove.
    mutating func remove(_ url: URL) {
        customRPCs.removeAll { $0 == url }
        if selection == .custom(url) { selection = .solana }
    }
}
