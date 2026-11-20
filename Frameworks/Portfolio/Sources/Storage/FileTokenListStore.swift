import Foundation
import RPC
import Storage
import Transactions

/// A store that saves one versioned JSON token list per account and network.
struct FileTokenListStore {
    let directory: URL
    private static let coding = VersionedJSONCoding<Saved>(version: 1, unusable: .unreadable)

    private var files: KeyedFiles { KeyedFiles(directory: directory) }

    /// Reads an account's saved list.
    ///
    /// - Parameter key: The account and network to look up.
    /// - Returns: The saved list, or `nil` if the account has none that can be used.
    /// - Throws: ``TokenListError/unreadable`` if the list's file can't be read.
    func tokenList(for key: CacheKey) throws -> TokenList? {
        let data: Data?
        do {
            data = try files.read(for: key)
        } catch {
            throw TokenListError.unreadable
        }
        guard let data, let saved = Self.coding.decode(data), saved.owner == key.owner,
              saved.network == key.network else { return nil }
        return TokenList(network: saved.network, mints: saved.mints)
    }

    /// Replaces an account's saved list.
    ///
    /// - Parameters:
    ///   - list: The complete list to save.
    ///   - key: The account and network under which to save it.
    /// - Throws: An encoding or file-system error.
    func save(_ list: TokenList, for key: CacheKey) throws {
        let saved = Saved(owner: key.owner, network: key.network, mints: list.mints)
        try files.write(Self.coding.encode(saved), for: key)
    }

    /// Removes an account's saved list, if present.
    ///
    /// - Parameter key: The account and network to remove.
    /// - Throws: A file-system error.
    func remove(for key: CacheKey) throws {
        try files.remove(for: key)
    }

    /// A saved token list, with its account and network.
    private struct Saved: Codable, Equatable, Sendable {
        let owner: String
        let network: Network
        let mints: [Mint]
    }
}
