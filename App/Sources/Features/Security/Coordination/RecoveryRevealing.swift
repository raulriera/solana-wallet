/// Reads a wallet's recovery so the user can write down a backup.
nonisolated protocol RecoveryRevealing: Sendable {
    /// Reads the wallet's recovery after the user authenticates with biometrics or the device passcode.
    /// - Parameter account: The window's wallet.
    /// - Returns: The backup, or ``RecoveryDisplay/unavailable`` when this device no longer has the recovery.
    /// - Throws: `CancellationError` if the user cancels authentication, or another storage error.
    func display(for account: Account) async throws -> RecoveryDisplay
}
