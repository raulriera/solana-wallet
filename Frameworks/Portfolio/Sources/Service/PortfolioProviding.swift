/// A type that provides wallet portfolios while encapsulating caching and refreshes.
///
/// Assign increasing `Update.revision` values across all streams from one provider instance.
/// Forwarded or replayed updates keep their revision; cached snapshots retain their original
/// `Update.snapshotRevision`. Consumers can then order data and status independently of wall time.
public protocol PortfolioProviding: Sendable {
    /// Observes confirmed account changes for the lifetime of the consuming task.
    ///
    /// Shares one connection per wallet. Each new consumer requests a reload or joins one in progress.
    /// Setup completes before the initial reload; bursts of changes are coalesced into one balance read.
    /// Transport and rate-limit errors are surfaced without automatic retries or reconnects.
    /// The app owns starting and cancelling observation with its foreground/view lifecycle.
    /// - Parameter owner: The wallet whose holdings to observe.
    /// - Returns: A stream of cached state and refresh results, ending on cancellation or subscription failure.
    func observations(for owner: String) async -> AsyncStream<Update>

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

    /// Revalues cached holdings through the injected price provider without reading balances again.
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
    /// - Returns: A finite sequence of portfolio states without reading balances again.
    public func priceUpdates(for owner: String) async -> AsyncStream<Update> {
        await priceUpdates(for: owner, policy: .ifStale)
    }
}
