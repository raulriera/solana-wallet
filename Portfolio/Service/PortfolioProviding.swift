/// A type that provides wallet portfolios while encapsulating caching and refreshes.
public protocol PortfolioProviding: Sendable {
    /// Returns cached portfolio state and refreshes the data required by the policy.
    ///
    /// The consumer is registered before this method returns. Network results arrive through the stream.
    ///
    /// - Parameters:
    ///   - owner: The wallet address whose portfolio to retrieve.
    ///   - policy: Reuse data younger than five minutes, or reload regardless of age.
    /// - Returns: One ready cached state when fresh, otherwise initial state followed
    ///   by a completed or failed refresh. Failures retain the latest complete snapshot.
    func updates(for owner: String, policy: RefreshPolicy) async -> AsyncStream<Update>

    /// Revalues cached holdings through the injected price provider without querying DAS.
    ///
    /// A concurrent full refresh can satisfy this request. No polling or retries are scheduled.
    /// - Parameters:
    ///   - owner: The wallet whose cached holdings to revalue.
    ///   - policy: Whether to reuse fresh prices or reload them regardless of age.
    /// - Returns: Cached state followed by updated valuations, or an error retaining cached state.
    ///   Missing holdings or a missing price provider produce a `PriceError` in the failed update.
    func priceUpdates(for owner: String, policy: RefreshPolicy) async -> AsyncStream<Update>

    /// Removes locally retained portfolio data and cancels its active refresh.
    ///
    /// - Parameter owner: The wallet whose local data to remove.
    /// - Throws: A file-system error if the stored snapshot can't be removed.
    func removeData(for owner: String) async throws
}

extension PortfolioProviding {
    /// Returns cached data, refreshing only when holdings or independent prices are stale or missing.
    /// - Parameter owner: The wallet whose portfolio to retrieve.
    /// - Returns: A finite sequence of portfolio states using the five-minute freshness policy.
    public func updates(for owner: String) async -> AsyncStream<Update> {
        await updates(for: owner, policy: .ifStale)
    }

    /// Returns cached prices, refreshing only when the last independent lookup is stale or missing.
    /// - Parameter owner: The wallet whose existing holdings to revalue.
    /// - Returns: A finite sequence of portfolio states without querying DAS.
    public func priceUpdates(for owner: String) async -> AsyncStream<Update> {
        await priceUpdates(for: owner, policy: .ifStale)
    }
}
