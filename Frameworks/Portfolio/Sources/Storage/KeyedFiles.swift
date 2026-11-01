import CryptoKit
import Encoding
import Foundation
import RPC

/// A directory with one file per wallet and network, each named by a digest of both.
struct KeyedFiles: Sendable {
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

    /// Reads every wallet's file in the directory.
    ///
    /// - Returns: The contents of each readable file, in no particular order.
    /// - Throws: A file-system error if the directory exists but can't be listed.
    func readAll() throws -> [Data] {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        return urls.filter { $0.pathExtension == "json" }.compactMap { try? Data(contentsOf: $0) }
    }

    /// Atomically replaces a wallet's file.
    ///
    /// - Parameters:
    ///   - data: The complete new contents.
    ///   - key: The wallet and network under which to store them.
    /// - Throws: A file-system error.
    func write(_ data: Data, for key: CacheKey) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: key), options: [.atomic, .completeFileProtection])
    }

    /// Removes a wallet's file, if present.
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

    /// Returns the URL of a wallet's file.
    ///
    /// - Parameter key: The wallet and network.
    /// - Returns: A JSON file URL inside the directory.
    private func fileURL(for key: CacheKey) -> URL {
        let data = Data("\(key.network.rawValue):\(key.owner)".utf8)
        let digest = Hex.encode(Array(SHA256.hash(data: data)))
        return directory.appendingPathComponent(digest).appendingPathExtension("json")
    }
}
