public import Redaction
public import Wallet

/// The recovery material shared by accounts derived from one seed.
public struct Recovery: Sendable, Redacted {
    public let phrase: RecoveryPhrase
    /// The BIP-39 passphrase, or an empty string for none.
    public let passphrase: String

    /// Creates recovery material.
    ///
    /// - Parameters:
    ///   - phrase: The validated recovery phrase.
    ///   - passphrase: The original BIP-39 passphrase; an empty string means none.
    public init(phrase: RecoveryPhrase, passphrase: String) {
        self.phrase = phrase
        self.passphrase = passphrase
    }
}
