import Transactions

/// One simulation of a proposed transaction, with what its review shows and what its record says.
nonisolated struct ProposedTransaction<Review: Equatable & Sendable>: Sendable {
    let simulation: Simulation
    /// What the review shows about the transaction.
    let review: Review
    let kind: TransactionRecord.Kind
    let settling: (any TransactionSettling)?
    /// Whether the proposal needs this transaction to succeed before it can prepare its own, such as one that makes
    /// the funds spendable.
    let isPreliminary: Bool

    /// Creates one simulation of a proposed transaction.
    ///
    /// - Parameters:
    ///   - simulation: The simulation that the person approves.
    ///   - review: What the review shows about the transaction.
    ///   - kind: What the record says that the transaction does.
    ///   - settling: What finishes the transaction's work once its outcome is found, or `nil` for nothing.
    ///   - isPreliminary: Whether the proposal needs this transaction to succeed before it can prepare its own.
    init(simulation: Simulation, review: Review, kind: TransactionRecord.Kind,
         settling: (any TransactionSettling)? = nil, isPreliminary: Bool = false) {
        self.simulation = simulation
        self.review = review
        self.kind = kind
        self.settling = settling
        self.isPreliminary = isPreliminary
    }
}
