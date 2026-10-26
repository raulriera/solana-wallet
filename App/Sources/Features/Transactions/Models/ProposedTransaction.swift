import Transactions

/// One simulation of a proposed transaction: what the person approves, what it shows them, and what the shared
/// transactions record once it's sent.
nonisolated struct ProposedTransaction<Review: Equatable & Sendable>: Sendable {
    /// The simulation that the person approves, which can be signed once.
    let simulation: Simulation
    /// What the review shows about the transaction, such as its fees.
    let review: Review
    /// What the record says that the transaction does.
    let kind: TransactionRecord.Kind
    /// What finishes the transaction's work once its outcome is found, if anything; it belongs to this simulation.
    let settling: (any TransactionSettling)?

    /// Creates one simulation of a proposed transaction.
    /// - Parameters:
    ///   - simulation: The simulation that the person approves.
    ///   - review: What the review shows about the transaction.
    ///   - kind: What the record says that the transaction does.
    ///   - settling: What finishes the transaction's work once its outcome is found, if anything.
    init(simulation: Simulation, review: Review, kind: TransactionRecord.Kind,
         settling: (any TransactionSettling)? = nil) {
        self.simulation = simulation
        self.review = review
        self.kind = kind
        self.settling = settling
    }
}
