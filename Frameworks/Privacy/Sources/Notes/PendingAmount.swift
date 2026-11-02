/// Lamports that a confirmed transaction gave the account, until a sync finds one of the transaction's notes included
/// or all of them spent.
struct PendingAmount: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let signature: String

    let lamports: UInt64

    var description: String { "PendingAmount" }

    var debugDescription: String { description }

    var customMirror: Mirror { Mirror(self, children: [:]) }
}
