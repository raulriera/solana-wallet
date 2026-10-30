/// A type that creates recovery phrases and derives Solana addresses locally.
public protocol WalletProviding: Sendable {
    /// Generates a recovery phrase from cryptographically secure randomness.
    ///
    /// - Parameter wordCount: The number of words in the generated phrase.
    /// - Returns: An English BIP-39 recovery phrase.
    /// - Throws: An error if secure randomness is unavailable.
    func recoveryPhrase(wordCount: RecoveryPhrase.WordCount) throws -> RecoveryPhrase

    /// Derives the accounts at the given paths.
    ///
    /// - Parameters:
    ///   - phrase: The validated recovery phrase.
    ///   - passphrase: The original BIP-39 passphrase, or an empty string for none.
    ///   - paths: The hardened paths to derive, in order.
    /// - Returns: The derived accounts, one for each path.
    /// - Throws: A cryptographic error or `CancellationError`.
    func accounts(for phrase: RecoveryPhrase, passphrase: String, paths: [DerivationPath]) async throws -> [DerivedAccount]
}
