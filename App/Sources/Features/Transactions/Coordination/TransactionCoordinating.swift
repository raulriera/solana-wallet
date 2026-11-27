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
    ///   - asset: The asset to pay, as the person reviewed it.
    ///   - wallet: The account that signs and pays the fees.
    ///   - recipient: The receiving wallet, or a token account for a token.
    ///   - source: The token account to pay from, or `nil` for the associated account.
    ///   - memo: The payment's memo, or `nil` for none.
    /// - Returns: The simulation to review.
    /// - Throws: ``Transactions/TokenError/accountMismatch`` if a token's mint account differs from the reviewed mint,
    ///   or a resolution, preparation, RPC, or cancellation error.
    func transfer(_ amount: UInt64, of asset: Asset, using wallet: Account, to recipient: Address,
                  source: Address?, memo: String?) async throws -> Simulation

    /// Signs an approved simulation without sending it.
    ///
    /// - Parameter simulation: The approved simulation.
    /// - Returns: The transaction with the local signatures added.
    /// - Throws: A validation, authentication, or signing error.
    func sign(_ simulation: Simulation) async throws -> Transaction

    /// Signs and sends an approved simulation without waiting for it to settle.
    ///
    /// - Parameter simulation: The approved simulation.
    /// - Returns: The transaction's pending outcome.
    /// - Throws: A validation, authentication, signing, or cancellation error.
    func submit(_ simulation: Simulation) async throws -> TransactionOutcome

    /// Runs an operation whose transactions share one authentication of a saved account's owner.
    ///
    /// - Parameter operation: The work to run. It signs and submits with the coordinator that it receives, which
    ///   accepts this coordinator's simulations: the first signature authenticates the owner, and later signatures
    ///   reuse that authentication until the operation ends.
    /// - Returns: The operation's result.
    /// - Throws: The operation's error.
    func withSharedAuthentication<Value: Sendable>(
        _ operation: @Sendable (any TransactionCoordinating) async throws -> Value
    ) async throws -> Value
}

extension TransactionCoordinating {
    /// Simulates a payment of SOL or a token from the account's associated token account.
    ///
    /// - Parameters:
    ///   - amount: The amount in lamports or raw token units.
    ///   - asset: The asset to pay, as the person reviewed it.
    ///   - wallet: The account that signs and pays the fees.
    ///   - recipient: The receiving wallet, or a token account for a token.
    /// - Returns: The simulation to review.
    /// - Throws: An error as ``transfer(_:of:using:to:source:memo:)`` describes.
    func transfer(_ amount: UInt64, of asset: Asset, using wallet: Account,
                  to recipient: Address) async throws -> Simulation {
        try await transfer(amount, of: asset, using: wallet, to: recipient, source: nil, memo: nil)
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
