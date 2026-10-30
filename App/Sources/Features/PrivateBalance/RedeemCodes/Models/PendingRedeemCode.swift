import Foundation

/// An index that a code's preparation took and whose funding isn't recorded yet.
nonisolated struct PendingRedeemCode: Codable, Equatable, Sendable {
    /// How long after its preparation a code's funding can still land, in seconds.
    static let lifetime: TimeInterval = 3_600

    let index: UInt32
    /// When the code was prepared.
    let created: Date

    /// Returns whether the code's funding has expired.
    ///
    /// - Parameter date: The current date.
    /// - Returns: `true` once more than ``lifetime`` passed since the code was prepared.
    func isExpired(at date: Date) -> Bool {
        date.timeIntervalSince(created) > Self.lifetime
    }
}
