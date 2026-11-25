import RPC

/// What happened to a sent transaction.
nonisolated struct Outcome: Codable, Equatable, Sendable {
    /// The transaction's first signature, which identifies it.
    let signature: String
    let network: Network
    let lastValidBlockHeight: UInt64
    let status: Status

    /// Whether a sent transaction landed, and how it ran.
    enum Status: Codable, Equatable, Sendable {
        /// The transaction hasn't landed, and can still land.
        case pending
        case succeeded(slot: UInt64)
        /// The transaction ran and failed; its fee was paid.
        case failed(slot: UInt64, ExecutionError)
        /// The transaction can never land.
        case dropped
    }
}
