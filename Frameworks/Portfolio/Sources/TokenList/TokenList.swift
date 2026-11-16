public import RPC
public import Transactions

/// The tokens an account lists besides native SOL.
public struct TokenList: Sendable, Equatable {
    /// The most tokens a list holds, counting native SOL.
    public static let tokenLimit = 50

    public let network: Network
    /// The remaining default tokens, followed by added tokens in the order they were added.
    public private(set) var mints: [Mint]

    /// Creates a list from saved tokens.
    ///
    /// - Parameters:
    ///   - network: The network whose tokens the list holds.
    ///   - mints: The tokens' mints in display order.
    init(network: Network, mints: [Mint]) {
        self.network = network
        self.mints = mints
    }

    /// Creates the list an account starts with on a network.
    ///
    /// - Parameter network: The network whose default tokens to list.
    /// - Throws: A validation error if a built-in mint address is malformed.
    init(defaultsFor network: Network) throws {
        self.init(network: network, mints: try Self.defaultMints(for: network))
    }

    /// Adds a token after the listed ones, if it isn't listed yet.
    ///
    /// - Parameter mint: The mint of the token to add.
    /// - Throws: ``TokenListError/limitReached`` if the list, with native SOL, already holds ``tokenLimit`` tokens.
    mutating func add(_ mint: Mint) throws {
        guard !mints.contains(where: { $0.address == mint.address }) else { return }
        guard mints.count + 1 < Self.tokenLimit else { throw TokenListError.limitReached }
        mints.append(mint)
    }

    /// Removes a token from the list.
    ///
    /// - Parameter mint: The mint address of the token to remove.
    mutating func remove(_ mint: Address) {
        mints.removeAll { $0.address == mint }
    }

    /// Returns the accounts that hold the list's balances.
    ///
    /// - Parameter owner: The wallet address.
    /// - Returns: The wallet, then each listed token's associated token account in list order.
    /// - Throws: A derivation error if a token's associated account address can't be derived.
    func accounts(of owner: Address) throws -> [Address] {
        try [owner] + mints.map { try $0.program.associatedAccount(owner: owner, mint: $0.address) }
    }

    /// Returns the mints of the tokens a new account starts with on a network.
    ///
    /// - Parameter network: The network whose defaults to list.
    /// - Returns: USDC and USDT on mainnet, or no tokens on devnet.
    /// - Throws: A validation error if a built-in mint address is malformed.
    private static func defaultMints(for network: Network) throws -> [Mint] {
        switch network {
        case .mainnet:
            [Mint(address: try Address("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"), program: .token, decimals: 6,
                  metadata: TokenMetadata(name: "USD Coin", symbol: "USDC")),
             Mint(address: try Address("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"), program: .token, decimals: 6,
                  metadata: TokenMetadata(name: "Tether USD", symbol: "USDT"))]
        case .devnet:
            []
        }
    }
}
