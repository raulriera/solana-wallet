/// A replaceable source of market prices, independent of wallet holdings and DAS.
public protocol PriceProviding: Sendable {
    /// The network whose mint addresses identify the quoted assets.
    var network: Network { get }

    /// Retrieves available unit prices for the requested token mints.
    ///
    /// Providers own authentication, request batching and pacing, and response transformation.
    /// Missing dictionary entries mean no price is available, never a zero price.
    /// An empty input performs no requests. Failed batches throw without returning
    /// partial results; providers don't retry or schedule subsequent refreshes.
    ///
    /// - Parameter mints: Mint addresses on this provider's network; duplicates are ignored.
    /// - Returns: Available quotes keyed by their requested mint address.
    /// - Throws: A request, transport, response, or cancellation error.
    func prices(for mints: [String]) async throws -> [String: Quote]
}
