import RPC
import Transactions

/// An actor that serializes changes to each account's token list.
actor TokenListCoordinator {
    private let store: any TokenListStoring
    private let network: Network

    /// Creates a coordinator for one network's lists.
    ///
    /// - Parameters:
    ///   - store: The token-list store.
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

    /// Adds a token to an account's list and saves the list.
    ///
    /// - Parameters:
    ///   - token: The token to add.
    ///   - owner: The account's wallet address.
    /// - Returns: `true` if the token was new to the list.
    /// - Throws: A ``TokenListError`` or a file-system error.
    func add(_ token: ListedToken, for owner: String) throws -> Bool {
        let saved = try list(for: owner)
        var list = saved
        try list.add(token)
        try store.save(list, for: key(for: owner))
        return list != saved
    }

    /// Removes a token from an account's list and saves the list.
    ///
    /// - Parameters:
    ///   - mint: The mint address of the token to remove.
    ///   - owner: The account's wallet address.
    /// - Returns: `true` if the token was listed.
    /// - Throws: ``TokenListError/unreadable`` or a file-system error.
    func remove(_ mint: Address, for owner: String) throws -> Bool {
        let saved = try list(for: owner)
        var list = saved
        list.remove(mint)
        try store.save(list, for: key(for: owner))
        return list != saved
    }

    /// Removes an account's saved list.
    ///
    /// - Parameter owner: The account's wallet address.
    /// - Throws: A file-system error.
    func removeList(for owner: String) throws {
        try store.remove(for: key(for: owner))
    }

    /// Returns the storage key of an account's list.
    ///
    /// - Parameter owner: The account's wallet address.
    /// - Returns: The key for the account on the coordinator's network.
    private func key(for owner: String) -> CacheKey {
        CacheKey(owner: owner, network: network)
    }
}
