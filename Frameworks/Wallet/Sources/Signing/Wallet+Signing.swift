import Encoding
import CryptoKit
public import Foundation

extension Wallet: MessageSigning {
    /// Signs a message on the concurrent executor using the intended recovered account.
    ///
    /// The service retains no recovery material or private key after the call.
    /// Swift value lifetimes don't guarantee that secret bytes are erased from memory.
    /// This method signs the supplied bytes without parsing transaction intent.
    ///
    /// - Parameters:
    ///   - message: The exact unsigned message bytes; no signature or envelope is added.
    ///   - phrase: The validated recovery phrase.
    ///   - expectedAddress: The exact Base58 address that must match the recovered key.
    ///   - passphrase: The original BIP-39 passphrase.
    ///   - path: The account path.
    /// - Returns: A 64-byte Ed25519 signature. Signatures may vary between calls.
    /// - Throws: ``SigningError/signerMismatch`` for a different account,
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
        guard let expectedKey = Base58.decode(expectedAddress, byteCount: 32) else {
            throw SigningError.signerMismatch
        }
        let key = try KeyDerivation.signingKey(for: phrase, passphrase: passphrase, path: path)
        guard Array(key.publicKey.rawRepresentation) == expectedKey else {
            throw SigningError.signerMismatch
        }
        try Task.checkCancellation()
        let signature = try key.signature(for: message)
        try Task.checkCancellation()
        return signature
    }
}
