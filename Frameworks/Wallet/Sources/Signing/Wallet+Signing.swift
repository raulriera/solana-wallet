import CryptoKit
public import Foundation

extension Wallet: MessageSigning {
    /// Signs `message` on the concurrent executor with the recovered account; refuses Solana Rings
    /// key-derivation inputs before deriving a seed.
    ///
    /// - Parameters:
    ///   - message: The exact unsigned message bytes; no signature or envelope is added.
    ///   - phrase: The validated recovery phrase.
    ///   - expectedAddress: The exact Base58 address that must match the recovered key.
    ///   - passphrase: The original BIP-39 passphrase.
    ///   - path: The account path.
    /// - Returns: A 64-byte Ed25519 signature. Signatures may vary between calls.
    /// - Throws: ``SigningError/reservedMessage`` for a key derivation input,
    ///   ``SigningError/signerMismatch`` for a different account,
    ///   `CancellationError` if cancelled, or a cryptographic error.
    @concurrent
    public func signature(
        for message: Data,
        using phrase: RecoveryPhrase,
        expectedAddress: String,
        passphrase: String,
        path: DerivationPath
    ) async throws -> Data {
        try Task.checkCancellation()
        guard !message.isDerivationInput else { throw SigningError.reservedMessage }
        let signature = try Self.withVerifiedAccount(
            phrase, passphrase: passphrase, path: path, expectedAddress: expectedAddress,
            mismatch: SigningError.signerMismatch
        ) { key, _ in
            try Task.checkCancellation()
            return try key.signature(for: message)
        }
        try Task.checkCancellation()
        return signature
    }
}
