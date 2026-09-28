import RPC

/// An observed transaction outcome at confirmed or finalized commitment.
nonisolated struct Confirmation: Sendable, Equatable {
    /// The execution outcome, independently of confirmation progress.
    enum Outcome: Sendable, Equatable {
        /// The transaction executed without a reported error.
        case succeeded
        /// The transaction's execution failed with the provider's structured diagnostics.
        case failed(TransactionError)
    }

    /// The signature and network whose execution was observed.
    let submission: Submission
    /// The slot in which the transaction executed.
    let slot: UInt64
    /// The observed commitment; confirmed execution may not yet be finalized.
    let commitment: Commitment
    /// Whether execution succeeded or failed at the observed commitment.
    let outcome: Outcome

    /// Creates an execution observation without interpreting program-specific errors.
    ///
    /// - Parameters:
    ///   - submission: The accepted signature and network.
    ///   - slot: The transaction's execution slot.
    ///   - commitment: The observed confirmed or finalized commitment.
    ///   - outcome: The execution result, retaining structured failure details.
    init(submission: Submission, slot: UInt64, commitment: Commitment, outcome: Outcome) {
        self.submission = submission
        self.slot = slot
        self.commitment = commitment
        self.outcome = outcome
    }
}
