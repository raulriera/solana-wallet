/// The result of reading a wallet's recovery for backup.
nonisolated enum RecoveryDisplay: Sendable {
    case backup(RecoveryBackup)
    /// The wallet's recovery isn't on this device.
    case unavailable
}
