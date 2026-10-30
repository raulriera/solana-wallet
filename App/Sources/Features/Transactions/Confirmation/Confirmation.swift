import RPC

/// A sent transaction's finalized outcome, or proof that it can never land.
nonisolated struct Confirmation: Sendable, Equatable {
    /// A transaction's execution outcome.
    enum Outcome: Sendable, Equatable {
        case succeeded
        case failed(TransactionError)
        /// The transaction's blockhash expired before it landed.
        case dropped
    }

    let submission: Submission
    /// The slot in which the transaction executed, or `nil` if unknown.
    let slot: UInt64?
    let outcome: Outcome

    /// Creates a confirmation.
    ///
    /// - Parameters:
    ///   - submission: The transaction's receipt.
    ///   - slot: The transaction's execution slot, or `nil` if unknown.
    ///   - outcome: How the transaction settled.
    init(submission: Submission, slot: UInt64?, outcome: Outcome) {
        self.submission = submission
        self.slot = slot
        self.outcome = outcome
    }
}
