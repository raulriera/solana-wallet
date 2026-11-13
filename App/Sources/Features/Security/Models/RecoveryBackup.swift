import Redaction
import Wallet

/// The recovery phrase, passphrase, and account path that restore one wallet.
nonisolated struct RecoveryBackup: Sendable, Redacted {
    let phrase: RecoveryPhrase
    /// The BIP-39 passphrase, or an empty string when the wallet has none.
    let passphrase: String
    let path: DerivationPath
}
