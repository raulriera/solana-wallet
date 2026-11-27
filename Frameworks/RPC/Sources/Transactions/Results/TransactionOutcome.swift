/// What happened to a sent transaction.
public struct TransactionOutcome: Codable, Equatable, Sendable {
    /// The transaction's first signature, which identifies it.
    public let signature: String
    public let network: Network
    /// The highest block height at which the transaction can land; for an imported transaction, an upper bound.
    public let lastValidBlockHeight: UInt64
    public let status: Status

    public var isPending: Bool { status == .pending }

    /// Whether a sent transaction landed, and how it ran.
    public enum Status: Codable, Equatable, Sendable {
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
    public func settled(_ status: Status) -> TransactionOutcome {
        TransactionOutcome(signature: signature, network: network, lastValidBlockHeight: lastValidBlockHeight,
                           status: status)
    }
}
