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
    /// A slot whose ledger state includes the transaction, or `nil` if it never landed.
    let slot: UInt64?
    let outcome: Outcome

    /// Creates a confirmation.
    ///
    /// - Parameters:
    ///   - submission: The transaction's receipt.
    ///   - slot: A slot whose ledger state includes the transaction, or `nil` if it never landed.
    ///   - outcome: How the transaction settled.
    init(submission: Submission, slot: UInt64?, outcome: Outcome) {
        self.submission = submission
        self.slot = slot
        self.outcome = outcome
    }
}
