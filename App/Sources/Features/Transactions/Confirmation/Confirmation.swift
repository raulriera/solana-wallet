import RPC

/// A sent transaction's finalized outcome, or proof that it can never land.
nonisolated struct Confirmation: Sendable, Equatable {
    let submission: Submission
    /// A slot whose ledger state includes the transaction, or `nil` if it never landed.
    let slot: UInt64?
    let outcome: TransactionOutcome
}
