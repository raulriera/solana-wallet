import Foundation
import RPC

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

        /// A custom RPC's URL, or `nil` for a built-in provider.
        var customURL: URL? {
            if case .custom(let url) = self { url } else { nil }
        }
    }

    /// A custom RPC and the optional features that its server served when it was added.
    nonisolated struct CustomRPC: Codable, Equatable, Sendable {
        let url: URL
        let capabilities: Capabilities
    }

    /// The provider in use.
    var selection = Provider.solana
    /// The custom RPCs in the order they were added.
    var customRPCs: [CustomRPC] = []

    /// Returns the listed custom RPC at a URL.
    ///
    /// - Parameter url: The custom RPC's URL.
    /// - Returns: The custom RPC, or `nil` when the list doesn't hold the URL.
    func customRPC(for url: URL) -> CustomRPC? {
        customRPCs.first { $0.url == url }
    }

    /// Chooses the provider in use.
    ///
    /// - Parameter provider: The provider to use; a custom RPC must already be in the list.
    mutating func select(_ provider: Provider) {
        if case .custom(let url) = provider, customRPC(for: url) == nil { return }
        selection = provider
    }

    /// Adds a custom RPC, if it's new, and chooses it.
    ///
    /// - Parameters:
    ///   - url: The checked RPC URL.
    ///   - capabilities: The optional features that the RPC's server serves, saved only for a new RPC.
    mutating func add(_ url: URL, capabilities: Capabilities) {
        if customRPC(for: url) == nil { customRPCs.append(CustomRPC(url: url, capabilities: capabilities)) }
        select(.custom(url))
    }

    /// Removes a custom RPC, choosing Solana if it was in use.
    ///
    /// - Parameter url: The RPC URL to remove.
    mutating func remove(_ url: URL) {
        customRPCs.removeAll { $0.url == url }
        if selection == .custom(url) { selection = .solana }
    }
}
