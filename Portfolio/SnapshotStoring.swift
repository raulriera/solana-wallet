import RPC

/// The identity of a wallet's cached portfolio.
struct CacheKey: Hashable, Sendable {
    let owner: String
    let network: Network
}

/// A type that stores complete snapshots independently of the network source.
///
/// The portfolio coordinator serializes these synchronous operations off the main actor.
protocol SnapshotStoring: Sendable {
    /// Reads the most recent compatible snapshot for a wallet and network.
    ///
    /// - Parameter key: The wallet and network to look up.
    /// - Returns: The stored snapshot, or `nil` if unavailable or incompatible.
    func snapshot(for key: CacheKey) -> Snapshot?

    /// Replaces a wallet's stored snapshot after a complete refresh.
    ///
    /// - Parameters:
    ///   - snapshot: The complete snapshot to persist.
    ///   - key: The wallet and network under which to store it.
    /// - Throws: An encoding or file-system error if the snapshot can't be saved.
    func save(_ snapshot: Snapshot, for key: CacheKey) throws

    /// Removes a wallet's stored snapshot, if present.
    ///
    /// - Parameter key: The wallet and network to remove.
    /// - Throws: A file-system error if an existing snapshot can't be removed.
    func remove(for key: CacheKey) throws
}
