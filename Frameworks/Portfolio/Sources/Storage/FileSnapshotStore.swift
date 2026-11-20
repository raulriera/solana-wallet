import Foundation
import RPC
import Storage

/// A store that persists one versioned JSON snapshot per wallet and network.
struct FileSnapshotStore: SnapshotStoring {
    let directory: URL
    private static let coding = VersionedJSONCoding<Snapshot>(version: 1, unusable: .unreadable)

    private var files: KeyedFiles { KeyedFiles(directory: directory) }

    func snapshot(for key: CacheKey) -> Snapshot? {
        guard let data = try? files.read(for: key), let snapshot = Self.coding.decode(data),
              snapshot.owner == key.owner, snapshot.network == key.network else { return nil }
        return snapshot
    }

    func snapshots() throws -> [Snapshot] {
        try files.readAll().compactMap(Self.coding.decode)
    }

    func save(_ snapshot: Snapshot, for key: CacheKey) throws {
        try files.write(Self.coding.encode(snapshot), for: key)
    }

    func remove(for key: CacheKey) throws {
        try files.remove(for: key)
    }
}
