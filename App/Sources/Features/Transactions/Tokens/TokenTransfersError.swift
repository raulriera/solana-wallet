import Transactions

/// An error for token accounts that can't supply a transfer's instructions.
nonisolated enum TokenTransfersError: Error, Sendable, Equatable {
    case missingAccount(Address)
    /// The epoch read comes from a slot before the account reads.
    case inconsistentAccounts
}
