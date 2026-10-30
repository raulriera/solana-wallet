import Wallet

/// A service that copies recovery words to this device only, for a limited time.
nonisolated protocol RecoveryCopying: Sendable {
    /// How long copied words stay available to paste.
    var lifetime: Duration { get }

    /// Copies the words in order, separated by spaces, replacing anything copied before.
    ///
    /// - Parameter phrase: The recovery phrase to copy.
    func copy(_ phrase: RecoveryPhrase)
}
