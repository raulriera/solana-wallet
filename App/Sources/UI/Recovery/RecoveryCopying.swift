import Wallet

/// Copies recovery words where only this device can paste them, for a limited time.
nonisolated protocol RecoveryCopying: Sendable {
    /// How long copied words stay available to paste.
    var lifetime: Duration { get }

    /// Copies the words in their original order, separated by spaces, replacing anything copied before.
    /// - Parameter phrase: The recovery phrase shown for backup.
    func copy(_ phrase: RecoveryPhrase)
}
