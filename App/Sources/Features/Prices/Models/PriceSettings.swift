import Foundation

/// The price provider in use and the custom price servers a person added.
nonisolated struct PriceSettings: Codable, Equatable, Sendable {
    /// A price provider.
    nonisolated enum Provider: Codable, Hashable, Sendable {
        case jupiter
        /// A person's own HTTPS price server.
        case custom(URL)
        /// No price provider, so prices make no network requests.
        case off

        /// The provider's name, or a custom server's host.
        var name: LocalizedStringResource {
            switch self {
            case .jupiter: "Jupiter"
            case .off: LocalizedStringResource("None", comment: "The price provider choice that turns prices off.")
            case .custom(let url):
                LocalizedStringResource("\(url.host() ?? "")", comment: "A custom price server's host, shown exactly as entered.")
            }
        }

        /// A custom price server's URL, or `nil` for a built-in provider.
        var customURL: URL? {
            if case .custom(let url) = self { url } else { nil }
        }
    }

    /// The provider in use.
    var selection = Provider.jupiter
    /// The custom price server URLs in the order they were added.
    var customServers: [URL] = []

    /// Chooses the provider in use.
    ///
    /// - Parameter provider: The provider to use; a custom server must already be in the list.
    mutating func select(_ provider: Provider) {
        if case .custom(let url) = provider, !customServers.contains(url) { return }
        selection = provider
    }

    /// Adds a custom price server, if it's new, and chooses it.
    ///
    /// - Parameter url: The checked price server URL.
    mutating func add(_ url: URL) {
        if !customServers.contains(url) { customServers.append(url) }
        select(.custom(url))
    }

    /// Removes a custom price server, choosing Jupiter if it was in use.
    ///
    /// - Parameter url: The price server URL to remove.
    mutating func remove(_ url: URL) {
        customServers.removeAll { $0 == url }
        if selection == .custom(url) { selection = .jupiter }
    }
}
