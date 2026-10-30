/// A Solana confirmation level.
public enum Commitment: String, Codable, Sendable {
    /// State that the node has processed.
    case processed

    /// State that the cluster has confirmed.
    case confirmed

    /// State that the cluster has finalized.
    case finalized
}
