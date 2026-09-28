import Transactions

/// A type that prepares native transfers or imported V1 transactions for review.
nonisolated protocol TransactionPreparing: Sendable {
    /// Builds a transfer and retrieves its fee, block-height expiry, and simulation.
    ///
    /// - Parameters:
    ///   - transfer: The validated sender, recipient, and positive lamport amount.
    ///   - configuration: The explicit priority fee and execution resource limits.
    /// - Returns: Review data that retains simulation failures and unknown fees.
    /// - Throws: A message-construction or RPC error, or `CancellationError` if cancelled.
    func prepare(_ transfer: Transfer, configuration: Configuration) async throws -> Preparation

    /// Validates and evaluates an imported transaction for a selected required signer.
    ///
    /// Existing signatures are verified locally. The message and blockhash aren't changed.
    /// Durable nonces aren't supported by this recent-blockhash workflow.
    ///
    /// - Parameters:
    ///   - transaction: The typed transaction received from the import boundary.
    ///   - signer: The required signer whose empty slot the wallet intends to fill.
    /// - Returns: Exact transaction data, fee, and simulation for explicit approval.
    /// - Throws: A validation or RPC error, or `CancellationError` if cancelled.
    func prepare(_ transaction: Transaction, for signer: Address) async throws -> Preparation
}
