public import Transactions

/// A token in an account's list, with what the portfolio needs to find and show its balance.
public struct ListedToken: Codable, Sendable, Equatable {
    /// The token's mint address, which identifies it in the list.
    public let mint: Address
    /// The program that owns the mint and its token accounts.
    public let program: TokenProgram
    /// The number of decimal places in the mint's base-unit amounts.
    public let decimals: UInt8
    /// The ticker symbol, if known.
    public let symbol: String?
    /// The display name, if known.
    public let name: String?

    /// Creates a listed token from its mint and display details.
    ///
    /// - Parameters:
    ///   - mint: The token's mint address.
    ///   - program: The program that owns the mint.
    ///   - decimals: The number of decimal places in base-unit amounts.
    ///   - symbol: The ticker symbol, or `nil` if unknown.
    ///   - name: The display name, or `nil` if unknown.
    public init(mint: Address, program: TokenProgram, decimals: UInt8, symbol: String?, name: String?) {
        self.mint = mint
        self.program = program
        self.decimals = decimals
        self.symbol = symbol
        self.name = name
    }
}
