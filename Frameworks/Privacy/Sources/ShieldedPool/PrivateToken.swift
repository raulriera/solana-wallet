public import Transactions

/// A token that private balances hold, with its mint address as the raw value.
public enum PrivateToken: String, Sendable, CaseIterable {
    /// Mainnet USDC.
    case usdc = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    /// Mainnet USDT.
    case usdt = "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"
    /// Devnet USDC.
    case devnetUSDC = "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU"

    /// The token's mint.
    public var mint: Address {
        get throws { try Address(rawValue) }
    }

    /// The pool asset of the token's notes.
    var asset: ConfidentialPlaintext.Asset {
        switch self {
        case .usdc: .usdc
        case .usdt: .usdt
        case .devnetUSDC: .devnetUSDC
        }
    }
}
