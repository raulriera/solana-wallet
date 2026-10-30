/// A source of the person's request in Settings to reset the appearance.
nonisolated protocol RecoveryRequesting: Sendable {
    /// Returns whether the person requested a reset.
    ///
    /// - Returns: Whether a reset is requested.
    /// - Throws: A preferences or cancellation error.
    func isRequested() async throws -> Bool

    /// Clears the reset request.
    ///
    /// - Throws: A preferences or cancellation error.
    func complete() async throws
}
