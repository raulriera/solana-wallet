public import Foundation

/// A type that signs bytes with a locally recovered Ed25519 account.
public protocol MessageSigning: Sendable {
    /// Signs a message after checking the recovered account against the intended signer.
    ///
    /// The caller supplies the exact message bytes and owns transaction validation
    /// and user consent. This operation doesn't authenticate, persist, or broadcast.
    ///
    /// - Parameters:
    ///   - message: The complete, unsigned message bytes to sign.
    ///   - phrase: The validated recovery phrase.
    ///   - expectedAddress: The exact Base58 address of the intended signer.
    ///   - passphrase: The original BIP-39 passphrase, including significant whitespace.
    ///   - path: The hardened derivation path of the intended account.
    /// - Returns: A 64-byte Ed25519 signature, without private key material.
    /// - Throws: ``SigningError/signerMismatch`` if the recovered account differs,
    ///   `CancellationError` if cancelled, or a cryptographic error.
    func signature(
        for message: Data,
        using phrase: RecoveryPhrase,
        expectedAddress: String,
        passphrase: String,
        path: DerivationPath
    ) async throws -> Data
}
