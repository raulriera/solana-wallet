import Foundation
public import RPC

/// A portfolio service that delivers persisted holdings and automatically refreshes them through DAS.
public struct Portfolio: PortfolioProviding {
    private let coordinator: RefreshCoordinator

    /// Creates a portfolio service with persistent storage in the app's cache directory.
    ///
    /// - Parameters:
    ///   - rpc: The RPC client supplying holdings and descriptive metadata.
    ///   - prices: A same-network price provider; `nil` keeps DAS valuations and disables price-only refreshes.
    public init(rpc: any RPC, prices: (any PriceProviding)? = nil) {
        self.init(rpc: rpc, store: FileSnapshotStore(directory: .cachesDirectory.appendingPathComponent("Portfolio")), prices: prices)
    }

    /// Creates a service with an injected snapshot store and page size.
    ///
    /// - Parameters:
    ///   - rpc: The RPC client supplying DAS data.
    ///   - store: The persistent snapshot store.
    ///   - pageSize: The DAS page size. The default is 1,000.
    ///   - prices: An optional same-network price provider.
    init(rpc: any RPC, store: any SnapshotStoring, pageSize: Int = 1_000, prices: (any PriceProviding)? = nil) {
        coordinator = RefreshCoordinator(source: SnapshotFetcher(rpc: rpc, pageSize: pageSize), store: store, prices: prices)
    }

    /// Returns existing state followed by one holdings refresh and the configured independent prices.
    ///
    /// The service owns cache lookup, pagination, persistence, and failure fallback.
    /// Each caller receives its own stream while concurrent callers share the refresh.
    /// Registration completes before this method returns; the refresh arrives through the stream.
    ///
    /// - Parameter owner: The wallet address whose holdings to retrieve.
    /// - Returns: A finite stream of complete states. Cancelling its consuming task
    ///   detaches that consumer without clearing cached data.
    public func updates(for owner: String) async -> AsyncStream<Update> {
        await coordinator.updates(for: owner)
    }

    /// Refreshes only valuations for existing holdings, retaining balances, metadata, and their retrieval time.
    /// - Parameter owner: The wallet whose cached holdings to revalue.
    /// - Returns: Cached state followed by refreshed prices or an error, without scheduling another cycle.
    public func priceUpdates(for owner: String) async -> AsyncStream<Update> {
        await coordinator.updates(for: owner, scope: .prices)
    }

    /// Removes locally retained holdings and stops the wallet's active refresh.
    ///
    /// - Parameter owner: The wallet whose local data to remove.
    /// - Throws: A file-system error if the persisted snapshot can't be removed.
    public func removeData(for owner: String) async throws {
        try await coordinator.removeData(for: owner)
    }
}
