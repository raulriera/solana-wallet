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

    /// Fetches token state and prepares a transfer through either first-party token program.
    ///
    /// - Parameters:
    ///   - mint: The mint address whose on-chain owner determines the token program.
    ///   - amount: The positive debit in raw token units, before any token transfer fee.
    ///   - sender: The token owner and transaction fee payer.
    ///   - recipient: The wallet receiving tokens in its associated token account.
    ///   - configuration: The explicit priority fee and execution resource limits.
    ///   - source: A specific token account, or `nil` to derive the sender's associated account.
    ///   - memo: An optional memo, required for accounts that enforce incoming memos.
    /// - Returns: Exact token intent, service tips, fee, expiry, and simulation for review.
    /// - Throws: An account, token validation, RPC, or cancellation error.
    func prepareTokenTransfer(mint: Address, amount: UInt64, from sender: Address, to recipient: Address,
                              configuration: Configuration, source: Address?, memo: String?) async throws -> Preparation

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

extension TransactionPreparing {
    /// Prepares a token transfer from the sender's associated account without a memo.
    ///
    /// - Parameters:
    ///   - mint: The token's on-chain mint address.
    ///   - amount: The positive debit in raw token units.
    ///   - sender: The token owner and fee payer.
    ///   - recipient: The wallet receiving the tokens.
    ///   - configuration: The explicit priority fee and execution resource limits.
    /// - Returns: The existing preparation value for review, signing, and submission.
    /// - Throws: A preparation error or cancellation.
    func prepareTokenTransfer(mint: Address, amount: UInt64, from sender: Address, to recipient: Address,
                              configuration: Configuration) async throws -> Preparation {
        try await prepareTokenTransfer(mint: mint, amount: amount, from: sender, to: recipient,
                                       configuration: configuration, source: nil, memo: nil)
    }
}
