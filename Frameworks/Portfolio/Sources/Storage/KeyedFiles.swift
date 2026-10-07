import CryptoKit
import Foundation
import RPC

/// One file per wallet and network, named by a digest so neither value becomes a path component.
struct KeyedFiles: Sendable {
    /// The directory that holds the files.
    let directory: URL

    /// Reads a wallet's file.
    ///
    /// - Parameter key: The wallet and network to look up.
    /// - Returns: The file's contents, or `nil` if the wallet has no file.
    /// - Throws: A file-system error other than a missing file.
    func read(for key: CacheKey) throws -> Data? {
        do {
            return try Data(contentsOf: fileURL(for: key))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    /// Atomically replaces a wallet's file, so an interrupted write preserves the previous contents.
    ///
    /// - Parameters:
    ///   - data: The complete new contents.
    ///   - key: The wallet and network under which to store them.
    /// - Throws: A file-system error if the write fails.
    func write(_ data: Data, for key: CacheKey) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Portfolio files stay unreadable while the device is locked; the portfolio only runs in the foreground.
        try data.write(to: fileURL(for: key), options: [.atomic, .completeFileProtection])
    }

    /// Removes a wallet's file, allowing one that's already absent.
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
    /// - Parameter key: The identity to encode.
    /// - Returns: A JSON file URL inside the directory.
    private func fileURL(for key: CacheKey) -> URL {
        let data = Data("\(key.network.rawValue):\(key.owner)".utf8)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest).appendingPathExtension("json")
    }
}
