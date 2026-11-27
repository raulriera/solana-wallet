import RPC

/// A type that runs a transaction's remaining work once the transaction settles.
nonisolated protocol TransactionSettling: Sendable {
    /// Runs the work that depends on how the transaction settled.
    ///
    /// - Parameter outcome: The transaction's settled outcome.
    func settle(_ outcome: TransactionOutcome) async
}
