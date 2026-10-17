/// Lamports that a confirmed transaction gave the account and that the indexer hasn't reported yet,
/// such as a deposit to the account or a spend's change.
///
/// A pending amount counts toward the account's total but can't be spent: a spend needs the note's
/// position in its tree, which only the indexer reports. Descriptions and reflection omit the
/// values.
struct PendingAmount: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The signature of the transaction that created the notes.
    let signature: String

    /// The notes' total, in lamports.
    let lamports: UInt64

    /// A description that omits the values.
    var description: String { "PendingAmount" }

    /// A debugging description that omits the values.
    var debugDescription: String { description }

    /// A reflection view that omits the values.
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
