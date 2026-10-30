import RPC

/// The identity of a wallet's cached portfolio.
struct CacheKey: Hashable, Sendable {
    let owner: String
    let network: Network
}

/// A type that stores complete snapshots.
protocol SnapshotStoring: Sendable {
    /// Reads a wallet's stored snapshot.
    ///
    /// - Parameter key: The wallet and network to look up.
    /// - Returns: The stored snapshot, or `nil` if unavailable or incompatible.
    func snapshot(for key: CacheKey) -> Snapshot?

    /// Reads every compatible stored snapshot.
    ///
    /// - Returns: The readable stored snapshots, in no particular order.
    /// - Throws: A file-system error if the stored snapshots can't be listed.
    func snapshots() throws -> [Snapshot]

    /// Replaces a wallet's stored snapshot.
    ///
    /// - Parameters:
    ///   - snapshot: The complete snapshot to save.
    ///   - key: The wallet and network under which to store it.
    /// - Throws: An encoding or file-system error.
    func save(_ snapshot: Snapshot, for key: CacheKey) throws

    /// Removes a wallet's stored snapshot, if present.
    ///
    /// - Parameter key: The wallet and network to remove.
    /// - Throws: A file-system error.
    func remove(for key: CacheKey) throws
}
