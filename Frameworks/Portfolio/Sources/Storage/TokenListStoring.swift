/// A type that saves each account's token list.
///
/// The token-list coordinator serializes these synchronous operations off the main actor.
protocol TokenListStoring: Sendable {
    /// Reads an account's saved list.
    ///
    /// - Parameter key: The account and network to look up.
    /// - Returns: The saved list, or `nil` if the account has none yet.
    /// - Throws: ``TokenListError/unreadable`` if a saved list exists but can't be read.
    func tokenList(for key: CacheKey) throws -> TokenList?

    /// Replaces an account's saved list.
    ///
    /// - Parameters:
    ///   - list: The complete list to save.
    ///   - key: The account and network under which to save it.
    /// - Throws: An encoding or file-system error if the list can't be saved.
    func save(_ list: TokenList, for key: CacheKey) throws

    /// Removes an account's saved list, if present.
    ///
    /// - Parameter key: The account and network to remove.
    /// - Throws: A file-system error if an existing list can't be removed.
    func remove(for key: CacheKey) throws
}
