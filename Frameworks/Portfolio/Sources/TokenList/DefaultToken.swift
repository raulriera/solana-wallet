/// A token that every new mainnet list holds besides native SOL, identified by its mint address.
public enum DefaultToken: String, CaseIterable, Sendable {
    /// USD Coin, issued by Circle.
    case usdc = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    /// Tether USD.
    case usdt = "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"
}
