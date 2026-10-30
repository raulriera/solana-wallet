public import Foundation

/// A type that signs messages with a recovered Ed25519 account.
public protocol MessageSigning: Sendable {
    /// Signs a message after checking the recovered account's address.
    ///
    /// - Parameters:
    ///   - message: The message bytes to sign.
    ///   - phrase: The validated recovery phrase.
    ///   - expectedAddress: The exact Base58 address of the intended signer.
    ///   - passphrase: The original BIP-39 passphrase.
    ///   - path: The hardened derivation path of the intended account.
    /// - Returns: A 64-byte Ed25519 signature.
    /// - Throws: ``SigningError/reservedMessage`` for a key derivation input,
    ///   ``SigningError/signerMismatch`` if the recovered account differs,
    ///   `CancellationError` if cancelled, or a cryptographic error.
    func signature(
        for message: Data,
        using phrase: RecoveryPhrase,
        expectedAddress: String,
        passphrase: String,
        path: DerivationPath
    ) async throws -> Data
}
