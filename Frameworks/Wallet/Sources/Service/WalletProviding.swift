/// A type that creates recovery phrases and derives Solana addresses locally.
public protocol WalletProviding: Sendable {
    /// Generates a recovery phrase from cryptographically secure randomness.
    ///
    /// - Parameter wordCount: The number of words in the generated phrase.
    /// - Returns: An English BIP-39 recovery phrase.
    /// - Throws: An error if secure randomness is unavailable.
    func recoveryPhrase(wordCount: RecoveryPhrase.WordCount) throws -> RecoveryPhrase

    /// Derives an ordered batch of accounts without checking network activity.
    /// - Parameters:
    ///   - phrase: The validated recovery phrase.
    ///   - passphrase: The original BIP-39 passphrase, or an empty string for none.
    ///   - paths: The explicit hardened paths, in result order.
    /// - Returns: Public addresses paired with their paths, preserving duplicates.
    /// - Throws: A cryptographic error or `CancellationError`.
    func accounts(for phrase: RecoveryPhrase, passphrase: String, paths: [DerivationPath]) async throws -> [DerivedAccount]
}
