public import Transactions

/// A type that keeps each account's token list on the device and looks up tokens to add to it.
///
/// Every account lists native SOL; the list holds the other tokens it shows.
public protocol TokenListProviding: Sendable {
    /// Adds a token to an account's list and saves the list.
    ///
    /// Adding a token that's already listed changes nothing.
    /// - Parameters:
    ///   - token: The token to add.
    ///   - owner: The account's wallet address.
    /// - Throws: ``TokenListError/limitReached`` if the list is full, ``TokenListError/unreadable``
    ///   if the saved list can't be read, or a file-system error if the list can't be saved.
    func addToken(_ token: ListedToken, for owner: String) async throws

    /// Removes a token from an account's list and saves the list.
    ///
    /// - Parameters:
    ///   - mint: The mint address of the token to remove.
    ///   - owner: The account's wallet address.
    /// - Throws: ``TokenListError/unreadable`` if the saved list can't be read,
    ///   or a file-system error if the list can't be saved.
    func removeToken(_ mint: Address, for owner: String) async throws

    /// Looks up a token by its pasted mint address, so a person can check it before adding it.
    ///
    /// - Parameter mint: The pasted mint address.
    /// - Returns: The token with its on-chain name and symbol, and its logo when the provider has one.
    /// - Throws: ``TokenLookupError`` when the address isn't a fungible token mint, or a request error.
    func token(at mint: Address) async throws -> TokenPreview
}
