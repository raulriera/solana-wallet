import Transactions

/// An error for token accounts that can't supply a transfer's instructions.
nonisolated enum TokenTransfersError: Error, Sendable, Equatable {
    case missingAccount(Address)
    /// The account reads have an unexpected count or an older ledger context.
    case inconsistentAccounts
}
