import Foundation
import RPC

/// A store that saves one versioned JSON token list per account and network.
struct FileTokenListStore: TokenListStoring {
    let directory: URL
    private static let version = 1

    private var files: KeyedFiles { KeyedFiles(directory: directory) }

    /// Reads a saved list, failing instead of reporting no list when a saved one can't be read.
    ///
    /// - Parameter key: The account and network to look up.
    /// - Returns: The saved list, or `nil` if the account has none yet.
    /// - Throws: ``TokenListError/unreadable`` if the file can't be read, decoded, or matched to the account.
    func tokenList(for key: CacheKey) throws -> TokenList? {
        let data: Data?
        do {
            data = try files.read(for: key)
        } catch {
            // Callers handle every read failure the same way, so file-system details stay inside the store.
            throw TokenListError.unreadable
        }
        guard let data else { return nil }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data), envelope.version == Self.version,
              envelope.owner == key.owner, envelope.network == key.network else { throw TokenListError.unreadable }
        return TokenList(network: envelope.network, tokens: envelope.tokens)
    }

    /// Atomically replaces a saved list so an interrupted write preserves the previous one.
    ///
    /// - Parameters:
    ///   - list: The complete list to save.
    ///   - key: The account and network under which to save it.
    /// - Throws: An encoding or file-system error if the write fails.
    func save(_ list: TokenList, for key: CacheKey) throws {
        let envelope = Envelope(version: Self.version, owner: key.owner, network: key.network, tokens: list.tokens)
        try files.write(JSONEncoder().encode(envelope), for: key)
    }

    /// Removes a saved list, allowing a file that's already absent.
    ///
    /// - Parameter key: The account and network to remove.
    /// - Throws: A file-system error other than a missing file.
    func remove(for key: CacheKey) throws {
        try files.remove(for: key)
    }

    /// A versioned envelope that identifies the list's account and network.
    private struct Envelope: Codable {
        let version: Int
        let owner: String
        let network: Network
        let tokens: [ListedToken]
    }
}
