import RPC

/// What happened to a sent transaction.
nonisolated struct TransactionOutcome: Codable, Equatable, Sendable {
    /// The transaction's first signature, which identifies it.
    let signature: String
    let network: Network
    /// The highest block height at which the transaction can land; for an imported transaction, an upper bound.
    let lastValidBlockHeight: UInt64
    let status: Status

    var isPending: Bool { status == .pending }

    /// Whether a sent transaction landed, and how it ran.
    enum Status: Codable, Equatable, Sendable {
        /// The transaction isn't finalized yet but can still be.
        case pending
        case succeeded
        /// The transaction landed and failed; its fee was paid.
        case failed
        /// The transaction can never land.
        case dropped
    }

    /// Returns this outcome with another status.
    ///
    /// - Parameter status: The new status.
    /// - Returns: The outcome.
    func settled(_ status: Status) -> TransactionOutcome {
        TransactionOutcome(signature: signature, network: network, lastValidBlockHeight: lastValidBlockHeight,
                           status: status)
    }
}
