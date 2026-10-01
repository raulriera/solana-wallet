/// A Solana confirmation level used in requests and transaction status responses.
public enum Commitment: String, Codable, Sendable {
    /// Uses state that the node has processed.
    case processed

    /// Uses state that the cluster has confirmed.
    case confirmed

    /// Uses state that the cluster has finalized.
    case finalized
}
