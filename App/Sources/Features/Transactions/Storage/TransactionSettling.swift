/// Finishes what a transaction started once its outcome is found, such as recording a private move in the account's
/// private balance.
///
/// A settling lives in memory with the transaction's watch and runs once, after the outcome is saved.
nonisolated protocol TransactionSettling: Sendable {
    /// Finishes the transaction's work after its outcome is found.
    /// - Parameter confirmation: The transaction's settled outcome.
    func settle(_ confirmation: Confirmation) async
}
