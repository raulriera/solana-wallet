/// A type that finishes a transaction's work once its outcome is found.
nonisolated protocol TransactionSettling: Sendable {
    /// Finishes the transaction's work.
    ///
    /// - Parameter outcome: The transaction's settled outcome.
    func settle(_ outcome: Outcome) async
}
