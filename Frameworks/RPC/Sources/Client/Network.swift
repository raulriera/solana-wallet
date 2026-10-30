/// A Solana network that can receive remote procedure calls.
public enum Network: String, Codable, Sendable, Hashable, CaseIterable {
    case mainnet

    case devnet
}
