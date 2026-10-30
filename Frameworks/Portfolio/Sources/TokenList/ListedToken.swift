public import Transactions

/// A token in an account's token list.
public struct ListedToken: Codable, Sendable, Equatable {
    public let mint: Address
    public let program: TokenProgram
    public let decimals: UInt8
    /// The ticker symbol.
    public let symbol: String?
    public let name: String?

    /// Creates a listed token.
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
