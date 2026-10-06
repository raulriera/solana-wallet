import CryptoKit
import Foundation
import RPC

/// A store that persists one versioned JSON snapshot per wallet and network.
struct FileSnapshotStore: SnapshotStoring {
    let directory: URL
    /// Older snapshots may hold NFTs or image links outside the provider's CDN, so they can't be reused.
    private static let version = 3

    /// Reads a stored snapshot, treating unavailable or incompatible files as cache misses.
    ///
    /// - Parameter key: The wallet and network to look up.
    /// - Returns: A matching snapshot, or `nil` if the file can't be used.
    func snapshot(for key: CacheKey) -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL(for: key)),
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
        let data = try JSONEncoder().encode(Envelope(version: Self.version, snapshot: snapshot))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Holdings stay unreadable while the device is locked; refreshes only run in the foreground.
        try data.write(to: fileURL(for: key), options: [.atomic, .completeFileProtection])
    }

    /// Removes a stored snapshot, allowing a file that's already absent.
    ///
    /// - Parameter key: The wallet and network to remove.
    /// - Throws: A file-system error other than a missing file.
    func remove(for key: CacheKey) throws {
        do {
            try FileManager.default.removeItem(at: fileURL(for: key))
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    /// Creates a safe filename from a wallet and network without using either as a path component.
    ///
    /// - Parameter key: The cache identity to encode.
    /// - Returns: A JSON file URL inside the cache directory.
    private func fileURL(for key: CacheKey) -> URL {
        let data = Data("\(key.network.rawValue):\(key.owner)".utf8)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest).appendingPathExtension("json")
    }

    /// A versioned envelope that allows incompatible cached formats to be ignored.
    private struct Envelope: Codable {
        let version: Int
        let snapshot: Snapshot
    }
}
