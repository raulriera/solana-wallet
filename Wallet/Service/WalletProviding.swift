/// A type that creates recovery phrases and derives Solana addresses locally.
public protocol WalletProviding: Sendable {
    /// Generates a recovery phrase from cryptographically secure randomness.
    ///
    /// - Parameter wordCount: The number of words in the generated phrase.
    /// - Returns: An English BIP-39 recovery phrase.
    /// - Throws: An error if secure randomness is unavailable.
    func recoveryPhrase(wordCount: RecoveryPhrase.WordCount) throws -> RecoveryPhrase

    /// Derives a Solana address from a validated recovery phrase.
    ///
    /// - Parameters:
    ///   - phrase: The recovery phrase used to derive the address.
    ///   - passphrase: The optional BIP-39 passphrase. An empty string means none.
    ///   - path: The hardened account path. Different paths produce different addresses.
    /// - Returns: The Base58-encoded Ed25519 public key.
    /// - Throws: `CancellationError` if cancelled, or a cryptographic error.
    func address(for phrase: RecoveryPhrase, passphrase: String, path: DerivationPath) async throws -> String
}
