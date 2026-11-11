/// The progress of a sent transaction.
public enum SignatureEvent: Sendable, Equatable {
    /// The transaction reached finalized commitment at a slot whose state includes it, with its execution error, or
    /// `nil` after it succeeded.
    case landed(slot: UInt64, error: TransactionError?)

    /// A new root slot, greater than every earlier one.
    case rooted(UInt64)
}
