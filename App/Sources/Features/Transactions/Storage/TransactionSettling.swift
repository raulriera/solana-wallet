/// A type that finishes a transaction's work once its outcome is found.
nonisolated protocol TransactionSettling: Sendable {
    /// Finishes the transaction's work.
    ///
    /// - Parameter confirmation: The transaction's settled outcome.
    func settle(_ confirmation: Confirmation) async
}
