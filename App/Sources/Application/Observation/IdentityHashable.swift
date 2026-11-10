/// A reference type whose instances equal only themselves and hash by identity, such as a model that drives a
/// presentation.
nonisolated protocol IdentityHashable: AnyObject, Hashable {}

nonisolated extension IdentityHashable {
    /// Returns whether two values are the same instance.
    ///
    /// - Parameters:
    ///   - lhs: A value to compare.
    ///   - rhs: Another value to compare.
    /// - Returns: `true` when both values are the same instance.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs === rhs
    }

    /// Hashes the instance's identity.
    ///
    /// - Parameter hasher: The hasher to feed.
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
