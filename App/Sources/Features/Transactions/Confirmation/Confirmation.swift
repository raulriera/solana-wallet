import RPC

/// A sent transaction's settled outcome: finalized execution, or finalized proof that it can never land.
nonisolated struct Confirmation: Sendable, Equatable {
    /// The execution outcome, independently of confirmation progress.
    enum Outcome: Sendable, Equatable {
        /// The transaction executed without a reported error.
        case succeeded
        /// The transaction's execution failed with the provider's structured diagnostics; it still paid its fee.
        case failed(TransactionError)
        /// The transaction can never land, because its blockhash expired at finalized commitment without it.
        case dropped
    }

    /// The signature and network whose outcome was observed.
    let submission: Submission
    /// The slot in which the transaction executed, when a status read reported it.
    ///
    /// A landing notification doesn't report the execution slot, and a dropped transaction has none.
    let slot: UInt64?
    /// Whether the transaction succeeded, failed, or was dropped.
    let outcome: Outcome

    /// Creates an outcome observation without interpreting program-specific errors.
    ///
    /// - Parameters:
    ///   - submission: The accepted signature and network.
    ///   - slot: The transaction's execution slot, or `nil` when the observation doesn't report it.
    ///   - outcome: The result, retaining structured failure details.
    init(submission: Submission, slot: UInt64?, outcome: Outcome) {
        self.submission = submission
        self.slot = slot
        self.outcome = outcome
    }
}
