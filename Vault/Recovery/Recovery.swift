public import Wallet

/// The material required to recover one wallet account.
///
/// Descriptions omit secrets. Explicit property access exposes them, and this
/// value doesn't guarantee memory erasure. Keep the original passphrase and path
/// with the recovery backup; different values derive different accounts.
public struct Recovery: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The validated BIP-39 recovery phrase.
    public let phrase: RecoveryPhrase
    /// The BIP-39 passphrase, including significant whitespace and case.
    public let passphrase: String
    /// The account's hardened derivation path.
    public let path: DerivationPath

    /// A description that omits recovery material.
    public var description: String { "Recovery" }
    /// A debugging description that omits recovery material.
    public var debugDescription: String { description }
    /// A reflection view that omits recovery material.
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Creates recovery material for a wallet account.
    ///
    /// - Parameters:
    ///   - phrase: The validated recovery phrase.
    ///   - passphrase: The original BIP-39 passphrase; an empty string means none.
    ///   - path: The account's original derivation path.
    public init(phrase: RecoveryPhrase, passphrase: String, path: DerivationPath) {
        self.phrase = phrase
        self.passphrase = passphrase
        self.path = path
    }
}
