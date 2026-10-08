public import RPC
import Transactions

/// The tokens an account lists besides native SOL, which every account keeps.
public struct TokenList: Sendable, Equatable {
    /// The most tokens a person can add, not counting the network's defaults.
    ///
    /// People who need more tokens use another account.
    public static let addedTokenLimit = 50

    /// The network whose tokens the list holds.
    public let network: Network
    /// The network's defaults that weren't removed, followed by added tokens in the order they were added.
    public private(set) var tokens: [ListedToken]

    /// Creates a list from saved tokens.
    ///
    /// - Parameters:
    ///   - network: The network whose tokens the list holds.
    ///   - tokens: The tokens in display order.
    init(network: Network, tokens: [ListedToken]) {
        self.network = network
        self.tokens = tokens
    }

    /// Creates the list an account starts with on a network.
    ///
    /// - Parameter network: The network whose default tokens to list.
    /// - Throws: A validation error if a built-in mint address is malformed.
    init(defaultsFor network: Network) throws {
        self.init(network: network, tokens: try Self.defaultTokens(for: network))
    }

    /// Adds a token after the listed ones; a token that's already listed keeps its place.
    ///
    /// - Parameter token: The token to add.
    /// - Throws: ``TokenListError/limitReached`` if the list already holds ``addedTokenLimit`` added tokens.
    mutating func add(_ token: ListedToken) throws {
        guard !tokens.contains(where: { $0.mint == token.mint }) else { return }
        let defaults = Set(try Self.defaultTokens(for: network).map(\.mint))
        // A default someone removed and adds again doesn't count toward the limit either.
        let addedCount = tokens.count { !defaults.contains($0.mint) }
        guard defaults.contains(token.mint) || addedCount < Self.addedTokenLimit else {
            throw TokenListError.limitReached
        }
        tokens.append(token)
    }

    /// Removes a token from the list.
    ///
    /// Native SOL isn't part of the list, so it always stays.
    /// - Parameter mint: The mint address of the token to remove.
    mutating func remove(_ mint: Address) {
        tokens.removeAll { $0.mint == mint }
    }

    /// Lists the accounts that hold the balances the list shows, which the portfolio reads and watches.
    ///
    /// - Parameter owner: The wallet that lists the tokens.
    /// - Returns: The wallet, then each listed token's associated token account in list order.
    /// - Throws: A derivation error if a token's associated account address can't be derived.
    func accounts(of owner: Address) throws -> [Address] {
        try [owner] + tokens.map { try $0.program.associatedAccount(owner: owner, mint: $0.mint) }
    }

    /// Lists the tokens a new account starts with on a network.
    ///
    /// Devnet has no official USDT, so devnet lists start empty.
    /// - Parameter network: The network whose defaults to list.
    /// - Returns: USDC and USDT on mainnet, or no tokens on devnet.
    /// - Throws: A validation error if a built-in mint address is malformed.
    private static func defaultTokens(for network: Network) throws -> [ListedToken] {
        switch network {
        case .mainnet:
            [ListedToken(mint: try Address("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"), program: .token, decimals: 6,
                         symbol: "USDC", name: "USD Coin"),
             ListedToken(mint: try Address("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"), program: .token, decimals: 6,
                         symbol: "USDT", name: "Tether USD")]
        case .devnet:
            []
        }
    }
}
