/// A source of market prices for token mints.
public protocol PriceProviding: Sendable {
    /// The network whose mints the provider quotes.
    var network: Network { get }

    /// Retrieves available unit prices for token mints.
    ///
    /// - Parameter mints: Mint addresses on the provider's network.
    /// - Returns: Available quotes keyed by mint address.
    /// - Throws: An ``RPCError`` or `CancellationError`.
    func prices(for mints: [String]) async throws -> [String: Quote]
}
