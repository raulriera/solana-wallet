public import Wallet

/// The recovery material shared by accounts derived from one seed.
public struct Recovery: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let phrase: RecoveryPhrase
    /// The BIP-39 passphrase, or an empty string for none.
    public let passphrase: String

    public var description: String { "Recovery" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }

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
