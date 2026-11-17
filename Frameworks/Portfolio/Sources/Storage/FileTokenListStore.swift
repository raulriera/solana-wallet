import Foundation
import RPC
import Transactions

/// A store that saves one versioned JSON token list per account and network.
struct FileTokenListStore {
    let directory: URL
    private static let version = 1

    private var files: KeyedFiles { KeyedFiles(directory: directory) }

    /// Reads an account's saved list.
    ///
    /// - Parameter key: The account and network to look up.
    /// - Returns: The saved list, or `nil` if the account has none yet.
    /// - Throws: ``TokenListError/unreadable`` if a saved list exists but can't be read.
    func tokenList(for key: CacheKey) throws -> TokenList? {
        let data: Data?
        do {
            data = try files.read(for: key)
        } catch {
            throw TokenListError.unreadable
        }
        guard let data else { return nil }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data), envelope.version == Self.version,
              envelope.owner == key.owner, envelope.network == key.network else { throw TokenListError.unreadable }
        return TokenList(network: envelope.network, mints: envelope.mints)
    }

    /// Replaces an account's saved list.
    ///
    /// - Parameters:
    ///   - list: The complete list to save.
    ///   - key: The account and network under which to save it.
    /// - Throws: An encoding or file-system error.
    func save(_ list: TokenList, for key: CacheKey) throws {
        let envelope = Envelope(version: Self.version, owner: key.owner, network: key.network, mints: list.mints)
        try files.write(JSONEncoder().encode(envelope), for: key)
    }

    /// Removes an account's saved list, if present.
    ///
    /// - Parameter key: The account and network to remove.
    /// - Throws: A file-system error.
    func remove(for key: CacheKey) throws {
        try files.remove(for: key)
    }

    /// A token list's file contents, with its format version, account, and network.
    private struct Envelope: Codable {
        let version: Int
        let owner: String
        let network: Network
        let mints: [Mint]
    }
}
