import Transactions

/// An error for token accounts that can't supply a transfer's instructions.
nonisolated enum TokenTransfersError: Error, Sendable, Equatable {
    case missingAccount(Address)
}
