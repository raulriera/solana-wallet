import Foundation
import RPC

/// A store that persists one versioned JSON snapshot per wallet and network.
struct FileSnapshotStore: SnapshotStoring {
    let directory: URL
    /// The stored format's version; a file with another version is a cache miss.
    private static let version = 4

    private var files: KeyedFiles { KeyedFiles(directory: directory) }

    /// Reads a stored snapshot, treating unavailable or incompatible files as cache misses.
    ///
    /// - Parameter key: The wallet and network to look up.
    /// - Returns: A matching snapshot, or `nil` if the file can't be used.
    func snapshot(for key: CacheKey) -> Snapshot? {
        guard let data = try? files.read(for: key), let snapshot = Self.decode(data),
              snapshot.owner == key.owner, snapshot.network == key.network else { return nil }
        return snapshot
    }

    /// Reads every stored snapshot in the current format.
    ///
    /// - Returns: The stored snapshots, skipping files that can't be used.
    /// - Throws: A file-system error if the directory exists but can't be listed.
    func snapshots() throws -> [Snapshot] {
        try files.readAll().compactMap(Self.decode)
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

    /// Decodes a stored snapshot in the current format.
    ///
    /// - Parameter data: A file's contents.
    /// - Returns: The snapshot, or `nil` if the contents aren't a snapshot in the current format.
    private static func decode(_ data: Data) -> Snapshot? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == version else { return nil }
        return envelope.snapshot
    }

    /// A versioned envelope that allows incompatible cached formats to be ignored.
    private struct Envelope: Codable {
        let version: Int
        let snapshot: Snapshot
    }
}
