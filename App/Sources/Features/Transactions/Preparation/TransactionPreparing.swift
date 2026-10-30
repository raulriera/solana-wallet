import Transactions

/// A type that prepares transactions for review.
nonisolated protocol TransactionPreparing: Sendable {
    /// Compiles and simulates instructions for review.
    ///
    /// - Parameters:
    ///   - instructions: The instructions, in order.
    ///   - payer: The account that pays the fees.
    ///   - signer: The account that signs.
    ///   - configuration: The priority fee and resource limits, or `nil` to estimate them.
    ///   - minimumSlot: The earliest slot for the provider's reads, or `nil` for any.
    /// - Returns: The transaction with its fee and simulation.
    /// - Throws: A validation, RPC, or cancellation error.
    func prepare(_ instructions: [Instruction], payer: Address, signer: Address,
                 configuration: Configuration?, minimumSlot: UInt64?) async throws -> Preparation

    /// Simulates an imported transaction without changing its message or signatures.
    ///
    /// - Parameters:
    ///   - transaction: The imported transaction.
    ///   - signer: The account whose empty signature slot gets filled.
    /// - Returns: The unchanged transaction with its fee and simulation.
    /// - Throws: A validation, RPC, or cancellation error.
    func prepare(_ transaction: Transaction, for signer: Address) async throws -> Preparation
}
