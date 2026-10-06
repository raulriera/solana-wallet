/// What the backup screen shows after the user authenticates.
nonisolated enum RecoveryDisplay: Sendable {
    /// The wallet's backup, ready to write down.
    case backup(RecoveryBackup)
    /// This device no longer has the wallet's recovery.
    case unavailable
}
