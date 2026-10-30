/// A service that reads a wallet's recovery for backup.
nonisolated protocol RecoveryRevealing: Sendable {
    /// Reads an account's recovery after the person authenticates.
    ///
    /// - Parameter account: The account whose recovery to read.
    /// - Returns: The backup, or ``RecoveryDisplay/unavailable`` when the recovery isn't on this device.
    /// - Throws: `CancellationError` if the person cancels authentication, or a storage error.
    func display(for account: Account) async throws -> RecoveryDisplay
}
