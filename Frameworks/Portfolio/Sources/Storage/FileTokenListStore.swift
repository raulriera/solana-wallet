import Foundation
import RPC

/// A store that saves one versioned JSON token list per account and network.
struct FileTokenListStore: TokenListStoring {
    let directory: URL
    private static let version = 1

    private var files: KeyedFiles { KeyedFiles(directory: directory) }

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
        return TokenList(network: envelope.network, tokens: envelope.tokens)
    }

    func save(_ list: TokenList, for key: CacheKey) throws {
        let envelope = Envelope(version: Self.version, owner: key.owner, network: key.network, tokens: list.tokens)
        try files.write(JSONEncoder().encode(envelope), for: key)
    }

    func remove(for key: CacheKey) throws {
        try files.remove(for: key)
    }

    /// A token list's file contents, with its format version, account, and network.
    private struct Envelope: Codable {
        let version: Int
        let owner: String
        let network: Network
        let tokens: [ListedToken]
    }
}
