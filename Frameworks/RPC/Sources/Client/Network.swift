/// A Solana network that can receive remote procedure calls.
public enum Network: String, Codable, Sendable, Hashable, CaseIterable {
    /// The production Solana network.
    case mainnet

    /// The Solana network used for development and testing.
    case devnet
}
