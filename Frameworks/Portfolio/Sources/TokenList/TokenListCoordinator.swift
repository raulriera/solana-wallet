import RPC
import Transactions

/// Serializes changes to each account's token list, so edits from several windows don't overwrite each other.
actor TokenListCoordinator {
    private let store: any TokenListStoring
    private let network: Network

    /// Creates a coordinator for one network's lists.
    ///
    /// - Parameters:
    ///   - store: The persistent token-list store.
    ///   - network: The network whose lists the coordinator keeps.
    init(store: any TokenListStoring, network: Network) {
        self.store = store
        self.network = network
    }

    /// Returns an account's saved list, or the network's defaults when the account has none yet.
    ///
    /// - Parameter owner: The account's wallet address.
    /// - Returns: The account's token list.
    /// - Throws: ``TokenListError/unreadable`` if a saved list can't be read.
    func list(for owner: String) throws -> TokenList {
        try store.tokenList(for: key(for: owner)) ?? TokenList(defaultsFor: network)
    }

    /// Adds a token and saves the list; an unreadable saved list stays in place.
    ///
    /// - Parameters:
    ///   - token: The token to add.
    ///   - owner: The account's wallet address.
    /// - Returns: The saved list, and whether the token was new to it.
    /// - Throws: ``TokenListError`` for a full or unreadable list, or a file-system error if saving fails.
    func add(_ token: ListedToken, for owner: String) throws -> (list: TokenList, changed: Bool) {
        let saved = try list(for: owner)
        var list = saved
        try list.add(token)
        try store.save(list, for: key(for: owner))
        return (list, list != saved)
    }

    /// Removes a token and saves the list; an unreadable saved list stays in place.
    ///
    /// - Parameters:
    ///   - mint: The mint address of the token to remove.
    ///   - owner: The account's wallet address.
    /// - Returns: The saved list, and whether the token was listed.
    /// - Throws: ``TokenListError/unreadable`` if the saved list can't be read, or a file-system error if saving fails.
    func remove(_ mint: Address, for owner: String) throws -> (list: TokenList, changed: Bool) {
        let saved = try list(for: owner)
        var list = saved
        list.remove(mint)
        try store.save(list, for: key(for: owner))
        return (list, list != saved)
    }

    /// Removes an account's saved list.
    ///
    /// - Parameter owner: The account's wallet address.
    /// - Throws: A file-system error if an existing list can't be removed.
    func removeList(for owner: String) throws {
        try store.remove(for: key(for: owner))
    }

    /// Identifies an account's list on this coordinator's network.
    ///
    /// - Parameter owner: The account's wallet address.
    /// - Returns: The storage key for the account and network.
    private func key(for owner: String) -> CacheKey {
        CacheKey(owner: owner, network: network)
    }
}
