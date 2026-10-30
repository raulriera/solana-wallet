public import Foundation

/// A provider that hosts copies of token logos on its own HTTPS image server.
public protocol LogoProviding: Sendable {
    /// Looks up the provider's copies of token logos.
    ///
    /// - Parameter mints: Mint addresses on the provider's network.
    /// - Returns: HTTPS logo URLs keyed by mint address.
    /// - Throws: An ``RPCError`` or `CancellationError`.
    func logos(for mints: [String]) async throws -> [String: URL]
}
