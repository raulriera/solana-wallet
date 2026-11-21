import Transactions

/// One simulation of a proposed transaction, with what its review shows and what its record says.
nonisolated struct ProposedTransaction<Review: Equatable & Sendable>: Sendable {
    let simulation: Simulation
    /// What the review shows about the transaction.
    let review: Review
    let kind: TransactionRecord.Kind
    let settling: (any TransactionSettling)?
    /// The number of transactions that the proposal still needs after this one succeeds, which is zero for the
    /// proposal's own transaction.
    let followingTransactions: Int

    /// Whether the proposal needs this transaction to succeed before it can prepare its own, such as one that makes
    /// the funds spendable.
    var isPreliminary: Bool { followingTransactions > 0 }

    /// Creates one simulation of a proposed transaction.
    ///
    /// - Parameters:
    ///   - simulation: The simulation that the person approves.
    ///   - review: What the review shows about the transaction.
    ///   - kind: What the record says that the transaction does.
    ///   - settling: What finishes the transaction's work once its outcome is found, or `nil` for nothing.
    ///   - followingTransactions: The number of transactions that the proposal still needs after this one succeeds.
    init(simulation: Simulation, review: Review, kind: TransactionRecord.Kind,
         settling: (any TransactionSettling)? = nil, followingTransactions: Int = 0) {
        self.simulation = simulation
        self.review = review
        self.kind = kind
        self.settling = settling
        self.followingTransactions = followingTransactions
    }
}
