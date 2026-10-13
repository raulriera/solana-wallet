/// Progress of a sent transaction, reported by a signature watch.
public enum SignatureEvent: Sendable, Equatable {
    /// The transaction reached finalized commitment, with its execution error, or `nil` after it succeeded.
    ///
    /// A failed transaction still pays its fee. The event has no slot, because a notification's
    /// context slot isn't guaranteed to be the slot in which the transaction executed.
    case landed(error: TransactionError?)

    /// A new root slot, greater than every earlier one.
    case rooted(UInt64)
}
