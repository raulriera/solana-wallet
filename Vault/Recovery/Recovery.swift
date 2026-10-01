public import Wallet

/// The recovery material shared by accounts derived from one seed.
///
/// Descriptions omit secrets. Explicit property access exposes them, and this
/// value doesn't guarantee memory erasure. Keep the original passphrase with the
/// recovery backup; changing it derives a different seed.
public struct Recovery: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The validated BIP-39 recovery phrase.
    public let phrase: RecoveryPhrase
    /// The BIP-39 passphrase, including significant whitespace and case.
    public let passphrase: String

    /// A description that omits recovery material.
    public var description: String { "Recovery" }
    /// A debugging description that omits recovery material.
    public var debugDescription: String { description }
    /// A reflection view that omits recovery material.
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Creates recovery material shared by derived accounts.
    ///
    /// - Parameters:
    ///   - phrase: The validated recovery phrase.
    ///   - passphrase: The original BIP-39 passphrase; an empty string means none.
    public init(phrase: RecoveryPhrase, passphrase: String) {
        self.phrase = phrase
        self.passphrase = passphrase
    }
}
