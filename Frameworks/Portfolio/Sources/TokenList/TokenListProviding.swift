public import Transactions

/// A type that keeps each account's token list on the device.
///
/// Every account lists native SOL; the list holds the other tokens it shows.
public protocol TokenListProviding: Sendable {
    /// Returns an account's saved list, or the network's defaults when the account has none yet.
    ///
    /// - Parameter owner: The account's wallet address.
    /// - Returns: The account's token list.
    /// - Throws: ``TokenListError/unreadable`` if a saved list exists but can't be read.
    func tokenList(for owner: String) async throws -> TokenList

    /// Adds a token to an account's list and saves the list.
    ///
    /// Adding a token that's already listed changes nothing.
    /// - Parameters:
    ///   - token: The token to add.
    ///   - owner: The account's wallet address.
    /// - Returns: The saved list.
    /// - Throws: ``TokenListError/limitReached`` if the list is full, ``TokenListError/unreadable``
    ///   if the saved list can't be read, or a file-system error if the list can't be saved.
    func addToken(_ token: ListedToken, for owner: String) async throws -> TokenList

    /// Removes a token from an account's list and saves the list.
    ///
    /// - Parameters:
    ///   - mint: The mint address of the token to remove.
    ///   - owner: The account's wallet address.
    /// - Returns: The saved list.
    /// - Throws: ``TokenListError/unreadable`` if the saved list can't be read,
    ///   or a file-system error if the list can't be saved.
    func removeToken(_ mint: Address, for owner: String) async throws -> TokenList
}
