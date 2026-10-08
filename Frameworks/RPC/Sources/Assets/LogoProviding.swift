public import Foundation

/// A provider that hosts copies of token logos on its own HTTPS image server.
public protocol LogoProviding: Sendable {
    /// The network whose mint addresses identify the logos.
    var network: Network { get }

    /// Looks up the provider's copies of token logos.
    ///
    /// Returns only HTTPS URLs on the provider's own image server, never creator-hosted or off-chain
    /// links, which would expose the viewer's IP address. A missing entry means the provider has no logo
    /// for that mint. An empty input sends no request. Providers batch within their limits and don't retry.
    /// - Parameter mints: Mint addresses on this provider's network; duplicates are ignored.
    /// - Returns: Logo URLs keyed by mint address.
    /// - Throws: A request, transport, response, or cancellation error.
    func logos(for mints: [String]) async throws -> [String: URL]
}
