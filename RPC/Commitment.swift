/// The confirmation level of the state used to answer a request.
public enum Commitment: String, Encodable, Sendable {
    /// Uses state that the node has processed.
    case processed

    /// Uses state that the cluster has confirmed.
    case confirmed

    /// Uses state that the cluster has finalized.
    case finalized
}
