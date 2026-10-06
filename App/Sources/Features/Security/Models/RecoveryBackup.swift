import Wallet

/// What restores one wallet: its words, original BIP-39 passphrase, and account path.
nonisolated struct RecoveryBackup: Sendable {
    /// The recovery words in backup order.
    let phrase: RecoveryPhrase
    /// The original BIP-39 passphrase, or an empty string when the wallet has none.
    let passphrase: String
    /// The exact path that derives the wallet's account.
    let path: DerivationPath
}
