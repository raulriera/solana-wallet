import Transactions

/// The app's review-and-approval boundary for arbitrary V1 transactions.
nonisolated protocol TransactionCoordinating: Sendable {
    /// Simulates ordered instructions with the first selected wallet paying fees.
    /// - Parameters:
    ///   - instructions: The program invocations composing one transaction.
    ///   - wallets: The local authorities selected to sign after approval.
    /// - Returns: An immutable review with no signatures added.
    /// - Throws: A preparation or cancellation error.
    func simulate(_ instructions: [Instruction], using wallets: [Account]) async throws -> Simulation

    /// Simulates imported bytes while preserving existing signatures.
    /// - Parameters:
    ///   - transaction: The unchanged imported V1 transaction.
    ///   - wallets: The local accounts whose signatures are requested.
    /// - Returns: An immutable review of the original transaction.
    /// - Throws: A validation, RPC, or cancellation error.
    func simulate(_ transaction: Transaction, using wallets: [Account]) async throws -> Simulation

    /// Resolves a payment into the shared instruction workflow.
    /// - Parameters:
    ///   - amount: Positive lamports or raw token units.
    ///   - token: The token mint, or `nil` for SOL.
    ///   - wallet: The authority and fee payer.
    ///   - recipient: The receiving wallet, or a token account for `token`.
    ///   - source: An optional non-associated token account.
    ///   - memo: An optional payment memo.
    /// - Returns: The simulated transaction and applicable payment observations.
    /// - Throws: A resolution, preparation, RPC, or cancellation error.
    func transfer(_ amount: UInt64, token: Address?, using wallet: Account, to recipient: Address,
                  source: Address?, memo: String?) async throws -> Simulation

    /// Signs an explicitly approved review without broadcasting it.
    /// - Parameter simulation: The unchanged review approved by the user.
    /// - Returns: The transaction with the selected local signatures added.
    /// - Throws: A validation, authentication, or signing error.
    func sign(_ simulation: Simulation) async throws -> Transaction

    /// Signs, submits, and observes a review after explicit approval.
    /// - Parameter simulation: The unchanged review approved by the user.
    /// - Returns: The on-chain execution outcome, including execution failures.
    /// - Throws: A validation, authentication, delivery, or observation error.
    func confirm(_ simulation: Simulation) async throws -> Confirmation
}

extension TransactionCoordinating {
    /// Resolves an ordinary payment without exposing token account setup.
    /// - Parameters:
    ///   - amount: Positive lamports or raw token units.
    ///   - token: The mint, or `nil` for SOL.
    ///   - wallet: The selected authority and fee payer.
    ///   - recipient: The receiving wallet, or a token account for `token`.
    /// - Returns: The exact simulated transaction for review.
    /// - Throws: A resolution, preparation, or cancellation error.
    func transfer(_ amount: UInt64, token: Address? = nil, using wallet: Account,
                  to recipient: Address) async throws -> Simulation {
        try await transfer(amount, token: token, using: wallet, to: recipient, source: nil, memo: nil)
    }

    /// Simulates instructions for one local wallet.
    /// - Parameters:
    ///   - instructions: Ordered invocations composing one atomic transaction.
    ///   - wallet: The selected local authority and fee payer.
    /// - Returns: The exact review for subsequent approval.
    /// - Throws: A preparation, RPC, or cancellation error.
    func simulate(_ instructions: [Instruction], using wallet: Account) async throws -> Simulation {
        try await simulate(instructions, using: [wallet])
    }

    /// Simulates an imported transaction for one local signer.
    /// - Parameters:
    ///   - transaction: The unchanged imported transaction.
    ///   - wallet: The selected local authority.
    /// - Returns: The exact review for subsequent approval.
    /// - Throws: A validation, RPC, or cancellation error.
    func simulate(_ transaction: Transaction, using wallet: Account) async throws -> Simulation {
        try await simulate(transaction, using: [wallet])
    }
}
