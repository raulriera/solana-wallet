import Transactions

/// A type that evaluates local instruction compositions and unchanged imported transactions.
nonisolated protocol TransactionPreparing: Sendable {
    /// Compiles and evaluates instructions for explicit review.
    ///
    /// - Parameters:
    ///   - instructions: The ordered program invocations.
    ///   - payer: The account paying network fees.
    ///   - signer: The selected wallet authority.
    ///   - configuration: Explicit resource requests, or `nil` for estimation.
    ///   - minimumSlot: The earliest permitted context for instruction prerequisites.
    /// - Returns: Exact transaction inspection, fees, and simulation diagnostics.
    /// - Throws: A validation, RPC, or cancellation error.
    func prepare(_ instructions: [Instruction], payer: Address, signer: Address,
                 configuration: Configuration?, minimumSlot: UInt64?) async throws -> Preparation

    /// Evaluates an imported transaction without modifying its message or signatures.
    ///
    /// - Parameters:
    ///   - transaction: The complete imported transaction.
    ///   - signer: The account whose empty required-signature slot will be filled.
    /// - Returns: The unchanged transaction and review observations.
    /// - Throws: A validation, RPC, or cancellation error.
    func prepare(_ transaction: Transaction, for signer: Address) async throws -> Preparation
}
