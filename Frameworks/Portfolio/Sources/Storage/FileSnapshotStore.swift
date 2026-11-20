import Foundation
import RPC

/// A store that persists one versioned JSON snapshot per wallet and network.
struct FileSnapshotStore: SnapshotStoring {
    let directory: URL
    private static let version = 1

    private var files: KeyedFiles { KeyedFiles(directory: directory) }

    func snapshot(for key: CacheKey) -> Snapshot? {
        guard let data = try? files.read(for: key), let snapshot = Self.decode(data),
              snapshot.owner == key.owner, snapshot.network == key.network else { return nil }
        return snapshot
    }

    func snapshots() throws -> [Snapshot] {
        try files.readAll().compactMap(Self.decode)
    }

    func save(_ snapshot: Snapshot, for key: CacheKey) throws {
        try files.write(JSONEncoder().encode(Envelope(version: Self.version, snapshot: snapshot)), for: key)
    }

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

    /// A snapshot's file contents, with its format version.
    private struct Envelope: Codable {
        let version: Int
        let snapshot: Snapshot
    }
}
