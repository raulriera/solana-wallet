import Foundation
import RPC

/// A store that persists one versioned JSON snapshot per wallet and network.
struct FileSnapshotStore: SnapshotStoring {
    let directory: URL
    /// Older snapshots may hold NFTs or image links outside the provider's CDN, so they can't be reused.
    private static let version = 3

    private var files: KeyedFiles { KeyedFiles(directory: directory) }

    /// Reads a stored snapshot, treating unavailable or incompatible files as cache misses.
    ///
    /// - Parameter key: The wallet and network to look up.
    /// - Returns: A matching snapshot, or `nil` if the file can't be used.
    func snapshot(for key: CacheKey) -> Snapshot? {
        guard let data = try? files.read(for: key),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == Self.version,
              envelope.snapshot.owner == key.owner,
              envelope.snapshot.network == key.network else { return nil }
        return envelope.snapshot
    }

    /// Atomically replaces a snapshot so an interrupted write preserves the previous file.
    ///
    /// - Parameters:
    ///   - snapshot: The complete portfolio snapshot.
    ///   - key: The wallet and network under which to store it.
    /// - Throws: An encoding or file-system error if the write fails.
    func save(_ snapshot: Snapshot, for key: CacheKey) throws {
        try files.write(JSONEncoder().encode(Envelope(version: Self.version, snapshot: snapshot)), for: key)
    }

    /// Removes a stored snapshot, allowing a file that's already absent.
    ///
    /// - Parameter key: The wallet and network to remove.
    /// - Throws: A file-system error other than a missing file.
    func remove(for key: CacheKey) throws {
        try files.remove(for: key)
    }

    /// A versioned envelope that allows incompatible cached formats to be ignored.
    private struct Envelope: Codable {
        let version: Int
        let snapshot: Snapshot
    }
}
