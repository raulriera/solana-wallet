import Foundation

/// An index that a code's preparation took and whose funding hasn't been recorded yet.
///
/// The codes entry keeps it from the preparation on, so no later code reuses the index, even if the app quits before
/// the funding's outcome is recorded. A funding that lands becomes a record, either at its completion or when a listing
/// finds its note; one that doesn't land is forgotten once its transaction can no longer land.
nonisolated struct PendingRedeemCode: Codable, Equatable, Sendable {
    /// How long after its preparation a code's funding can still land: well past the lifetime of the transaction's
    /// blockhash, in seconds.
    static let lifetime: TimeInterval = 3_600

    /// The index of the code's one-time account under the account's code root.
    let index: UInt32
    /// When the code was prepared.
    let created: Date

    /// Whether the code's funding can no longer land.
    /// - Parameter date: The current date.
    /// - Returns: `true` once more than ``lifetime`` passed since the code was prepared.
    func isExpired(at date: Date) -> Bool {
        date.timeIntervalSince(created) > Self.lifetime
    }
}
