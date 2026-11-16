public import Transactions

/// A token that private balances hold, with its mint and the pool's ID of it.
///
/// The built-in tokens create their mint addresses with `try!`. Each address is a constant in this file, and
/// decoding a constant gives the same result on every run, so a mistyped address fails every test that reads
/// the tokens.
public struct PrivateToken: Hashable, Sendable {
    // swift-format-ignore: NeverUseForceTry
    /// Mainnet USDC.
    public static let usdc = PrivateToken(mint: try! Address("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),
                                          poolID: 3)

    // swift-format-ignore: NeverUseForceTry
    /// Mainnet USDT.
    public static let usdt = PrivateToken(mint: try! Address("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"),
                                          poolID: 19)

    // swift-format-ignore: NeverUseForceTry
    /// Devnet USDC.
    public static let devnetUSDC = PrivateToken(mint: try! Address("4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU"),
                                                poolID: 59)

    /// The tokens that private balances hold.
    static let supported = [usdc, usdt, devnetUSDC]

    /// The token program of every token that private balances hold.
    static let program = TokenProgram.token

    public let mint: Address

    /// The pool's ID of the token.
    let poolID: UInt64

    /// Creates the supported token of a mint, or `nil` for a mint that private balances don't hold.
    ///
    /// - Parameter mint: The token's mint address.
    init?(mint: Address) {
        guard let token = Self.supported.first(where: { $0.mint == mint }) else { return nil }
        self = token
    }

    /// Creates a token.
    ///
    /// - Parameters:
    ///   - mint: The token's mint address.
    ///   - poolID: The pool's ID of the token.
    private init(mint: Address, poolID: UInt64) {
        self.mint = mint
        self.poolID = poolID
    }
}
