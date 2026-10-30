/// Lamports that a confirmed transaction gave the account and that the indexer hasn't reported yet.
struct PendingAmount: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let signature: String

    let lamports: UInt64

    var description: String { "PendingAmount" }

    var debugDescription: String { description }

    var customMirror: Mirror { Mirror(self, children: [:]) }
}
