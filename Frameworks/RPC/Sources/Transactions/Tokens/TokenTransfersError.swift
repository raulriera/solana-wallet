public import Transactions

/// An error for token accounts that can't supply a transfer's instructions.
public enum TokenTransfersError: Error, Sendable, Equatable {
    case missingAccount(Address)
}
