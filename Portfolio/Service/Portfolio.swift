import Foundation
public import RPC

/// A portfolio service that delivers persisted holdings and refreshes stale or explicitly reloaded data.
public struct Portfolio: PortfolioProviding {
    private let coordinator: RefreshCoordinator
    private let observer: ObservationCoordinator

    /// Creates a portfolio service with persistent storage in the app's cache directory.
    ///
    /// - Parameters:
    ///   - rpc: The RPC client supplying holdings and descriptive metadata.
    ///   - prices: A same-network price provider; `nil` keeps DAS valuations and disables price-only refreshes.
    ///   - changes: A same-network subscription provider; `nil` uses the RPC client's capability when available.
    public init(rpc: any RPC, prices: (any PriceProviding)? = nil, changes: (any AccountChangeProviding)? = nil) {
        self.init(rpc: rpc, store: FileSnapshotStore(directory: .cachesDirectory.appendingPathComponent("Portfolio")),
                  prices: prices, changes: changes)
    }

    /// Creates a service with an injected snapshot store and page size.
    ///
    /// - Parameters:
    ///   - rpc: The RPC client supplying DAS data.
    ///   - store: The persistent snapshot store.
    ///   - pageSize: The DAS page size. The default is 1,000.
    ///   - prices: An optional same-network price provider.
    ///   - now: The current time used to evaluate cache age and record price refreshes.
    ///   - changes: The optional confirmed-change provider, defaulting to the RPC client's capability.
    ///   - pause: Cancellable scheduling for coalescing and bounded indexer catch-up.
    init(rpc: any RPC, store: any SnapshotStoring, pageSize: Int = 1_000, prices: (any PriceProviding)? = nil,
         now: @escaping @Sendable () -> Date = { Date() }, changes: (any AccountChangeProviding)? = nil,
         pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        coordinator = RefreshCoordinator(source: SnapshotFetcher(rpc: rpc, pageSize: pageSize), store: store,
                                         prices: prices, now: now)
        observer = ObservationCoordinator(refresh: coordinator, changes: changes ?? (rpc as? any AccountChangeProviding),
                                          network: rpc.network, pause: pause)
    }

    /// Returns cached state, refreshing holdings and independent prices according to the policy.
    ///
    /// The service owns cache lookup, pagination, persistence, and failure fallback.
    /// Each caller receives its own stream while concurrent callers share the refresh.
    /// Registration completes before this method returns; the refresh arrives through the stream.
    ///
    /// - Parameters:
    ///   - owner: The wallet address whose holdings to retrieve.
    ///   - policy: Whether to reuse fresh data or reload when opening the view or refreshing explicitly.
    /// - Returns: A finite stream of complete states. Cancelling its consuming task
    ///   detaches that consumer without clearing cached data.
    public func updates(for owner: String, policy: RefreshPolicy) async -> AsyncStream<Update> {
        await coordinator.updates(for: owner, policy: policy)
    }

    /// Refreshes only valuations for existing holdings, retaining balances, metadata, and their retrieval time.
    /// - Parameters:
    ///   - owner: The wallet whose cached holdings to revalue.
    ///   - policy: Whether to reuse recent prices or request new quotes regardless of age.
    /// - Returns: Cached state followed by refreshed prices or an error, without scheduling another cycle.
    public func priceUpdates(for owner: String, policy: RefreshPolicy) async -> AsyncStream<Update> {
        await coordinator.updates(for: owner, scope: .prices, policy: policy)
    }

    /// Observes confirmed wallet changes and refreshes holdings after DAS catches up.
    /// - Parameter owner: The visible wallet to observe until its consuming task is cancelled.
    /// - Returns: Cached state, an initial reload, and event-driven refresh results; disconnects end with an error.
    public func observations(for owner: String) async -> AsyncStream<Update> {
        await observer.observations(for: owner)
    }

    /// Removes locally retained holdings and stops the wallet's active refresh.
    ///
    /// - Parameter owner: The wallet whose local data to remove.
    /// - Throws: A file-system error if the persisted snapshot can't be removed.
    public func removeData(for owner: String) async throws {
        await observer.stop(for: owner)
        try await coordinator.removeData(for: owner)
    }
}
