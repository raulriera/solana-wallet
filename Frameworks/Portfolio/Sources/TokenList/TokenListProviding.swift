public import Transactions

/// A type that keeps each account's token list on the device and looks up tokens to add to it.
public protocol TokenListProviding: Sendable {
    /// Adds a token to an account's list and saves the list.
    ///
    /// - Parameters:
    ///   - mint: The mint of the token to add.
    ///   - owner: The account's wallet address.
    /// - Throws: ``TokenListError/limitReached`` if the list is full, ``TokenListError/unreadable``
    ///   if the saved list can't be read, or a file-system error if the list can't be saved.
    func addToken(_ mint: Mint, for owner: String) async throws

    /// Removes a token from an account's list and saves the list.
    ///
    /// - Parameters:
    ///   - mint: The mint address of the token to remove.
    ///   - owner: The account's wallet address.
    /// - Throws: ``TokenListError/unreadable`` if the saved list can't be read,
    ///   or a file-system error if the list can't be saved.
    func removeToken(_ mint: Address, for owner: String) async throws

    /// Looks up a token by its mint address.
    ///
    /// - Parameter mint: The mint address.
    /// - Returns: The token and its logo.
    /// - Throws: ``TokenLookupError`` when the address isn't a fungible token mint, or a request error.
    func token(at mint: Address) async throws -> TokenPreview
}
