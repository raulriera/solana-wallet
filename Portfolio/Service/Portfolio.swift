import Foundation
public import RPC

/// A portfolio service that delivers persisted holdings and automatically refreshes them through DAS.
public struct Portfolio: PortfolioProviding {
    private let coordinator: RefreshCoordinator

    /// Creates a portfolio service with persistent storage in the app's cache directory.
    ///
    /// - Parameter rpc: The RPC client supplying all DAS portfolio data.
    public init(rpc: any RPC) {
        self.init(rpc: rpc, store: FileSnapshotStore(directory: .cachesDirectory.appendingPathComponent("Portfolio")))
    }

    /// Creates a service with an injected snapshot store and page size.
    ///
    /// - Parameters:
    ///   - rpc: The RPC client supplying DAS data.
    ///   - store: The persistent snapshot store.
    ///   - pageSize: The DAS page size. The default is 1,000.
    init(rpc: any RPC, store: any SnapshotStoring, pageSize: Int = 1_000) {
        coordinator = RefreshCoordinator(source: SnapshotFetcher(rpc: rpc, pageSize: pageSize), store: store)
    }

    /// Returns existing state followed by the outcome of one automatic DAS refresh.
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

    /// Removes locally retained holdings and stops the wallet's active refresh.
    ///
    /// - Parameter owner: The wallet whose local data to remove.
    /// - Throws: A file-system error if the persisted snapshot can't be removed.
    public func removeData(for owner: String) async throws {
        try await coordinator.removeData(for: owner)
    }
}
