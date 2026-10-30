import Transactions

/// A type that simulates, signs, sends, and watches transactions.
nonisolated protocol TransactionCoordinating: TransactionConfirming {
    /// Simulates instructions, with the first authority paying the fees.
    ///
    /// - Parameters:
    ///   - instructions: The instructions of one transaction, in order.
    ///   - authorities: The accounts that sign after approval, in signing order.
    /// - Returns: The simulation to review.
    /// - Throws: A preparation or cancellation error.
    func simulate(_ instructions: [Instruction], using authorities: [Authority]) async throws -> Simulation

    /// Simulates an imported transaction, keeping its signatures.
    ///
    /// - Parameters:
    ///   - transaction: The imported transaction.
    ///   - wallets: The accounts whose signatures are requested.
    /// - Returns: The simulation to review.
    /// - Throws: A validation, RPC, or cancellation error.
    func simulate(_ transaction: Transaction, using wallets: [Account]) async throws -> Simulation

    /// Simulates a payment of SOL or a token.
    ///
    /// - Parameters:
    ///   - amount: The amount in lamports or raw token units.
    ///   - token: The token mint, or `nil` for SOL.
    ///   - wallet: The account that signs and pays the fees.
    ///   - recipient: The receiving wallet, or a token account for `token`.
    ///   - source: The token account to pay from, or `nil` for the associated account.
    ///   - memo: The payment's memo, or `nil` for none.
    /// - Returns: The simulation to review.
    /// - Throws: A resolution, preparation, RPC, or cancellation error.
    func transfer(_ amount: UInt64, token: Address?, using wallet: Account, to recipient: Address,
                  source: Address?, memo: String?) async throws -> Simulation

    /// Signs an approved simulation without sending it.
    ///
    /// - Parameter simulation: The approved simulation.
    /// - Returns: The transaction with the local signatures added.
    /// - Throws: A validation, authentication, or signing error.
    func sign(_ simulation: Simulation) async throws -> Transaction

    /// Signs and sends an approved simulation without waiting for its outcome.
    ///
    /// - Parameter simulation: The approved simulation.
    /// - Returns: The transaction's receipt.
    /// - Throws: A validation, authentication, signing, or cancellation error, or a ``DeliveryError`` after signing.
    func submit(_ simulation: Simulation) async throws -> Submission
}

extension TransactionCoordinating {
    /// Simulates a payment of SOL or a token from the account's associated token account.
    ///
    /// - Parameters:
    ///   - amount: The amount in lamports or raw token units.
    ///   - token: The token mint, or `nil` for SOL.
    ///   - wallet: The account that signs and pays the fees.
    ///   - recipient: The receiving wallet, or a token account for `token`.
    /// - Returns: The simulation to review.
    /// - Throws: A resolution, preparation, or cancellation error.
    func transfer(_ amount: UInt64, token: Address? = nil, using wallet: Account,
                  to recipient: Address) async throws -> Simulation {
        try await transfer(amount, token: token, using: wallet, to: recipient, source: nil, memo: nil)
    }

    /// Simulates instructions, with the first account paying the fees.
    ///
    /// - Parameters:
    ///   - instructions: The instructions of one transaction, in order.
    ///   - wallets: The accounts that sign after approval, in signing order.
    /// - Returns: The simulation to review.
    /// - Throws: A preparation or cancellation error.
    func simulate(_ instructions: [Instruction], using wallets: [Account]) async throws -> Simulation {
        try await simulate(instructions, using: wallets.map(Authority.account))
    }

    /// Simulates instructions for one account.
    ///
    /// - Parameters:
    ///   - instructions: The instructions of one transaction, in order.
    ///   - wallet: The account that signs and pays the fees.
    /// - Returns: The simulation to review.
    /// - Throws: A preparation, RPC, or cancellation error.
    func simulate(_ instructions: [Instruction], using wallet: Account) async throws -> Simulation {
        try await simulate(instructions, using: [wallet])
    }

    /// Simulates an imported transaction for one account.
    ///
    /// - Parameters:
    ///   - transaction: The imported transaction.
    ///   - wallet: The account whose signature is requested.
    /// - Returns: The simulation to review.
    /// - Throws: A validation, RPC, or cancellation error.
    func simulate(_ transaction: Transaction, using wallet: Account) async throws -> Simulation {
        try await simulate(transaction, using: [wallet])
    }
}
