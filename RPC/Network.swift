/// A Solana network that can receive remote procedure calls.
public enum Network: Sendable, Equatable {
    /// The production Solana network.
    case mainnet

    /// The Solana network used for development and testing.
    case devnet
}
