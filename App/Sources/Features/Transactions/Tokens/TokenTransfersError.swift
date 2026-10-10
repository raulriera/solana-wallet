import Transactions

/// An account observation that cannot supply consistent instruction prerequisites.
nonisolated enum TokenTransfersError: Error, Sendable, Equatable {
    /// A required mint or source account is absent.
    case missingAccount(Address)
    /// Account observations have an unexpected count or an older ledger context.
    case inconsistentAccounts
}
