/// Reads and acknowledges the one-time appearance recovery request from system Settings.
nonisolated protocol RecoveryRequesting: Sendable {
    /// Checks for a pending reset without clearing it.
    /// - Returns: Whether the user enabled appearance recovery.
    /// - Throws: A preferences or cancellation error.
    func isRequested() async throws -> Bool

    /// Turns off the request after appearance preferences have been reset successfully.
    /// - Throws: A preferences or cancellation error; unacknowledged requests remain eligible for recovery.
    func complete() async throws
}
