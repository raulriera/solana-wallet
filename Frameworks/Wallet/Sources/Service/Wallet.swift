/// A service that creates recovery phrases, derives addresses, and signs locally without persistence.
public struct Wallet: WalletProviding {
    private let entropy: any EntropyProviding

    /// Creates a wallet service that uses the system's secure random number generator.
    public init() {
        entropy = SystemEntropy()
    }

    /// Creates a wallet service with an injected entropy source.
    ///
    /// - Parameter entropy: The source of cryptographically secure random bytes.
    init(entropy: any EntropyProviding) {
        self.entropy = entropy
    }

    /// Generates a recovery phrase from cryptographically secure randomness.
    ///
    /// - Parameter wordCount: The number of words to generate.
    /// - Returns: An English BIP-39 recovery phrase for the caller to back up.
    /// - Throws: An error if the entropy source fails or returns an invalid byte count.
    public func recoveryPhrase(wordCount: RecoveryPhrase.WordCount) throws -> RecoveryPhrase {
        let bytes = try entropy.bytes(count: wordCount.entropyByteCount)
        guard bytes.count == wordCount.entropyByteCount else {
            throw RecoveryPhrase.ValidationError.invalidEntropy
        }
        return try RecoveryPhrase(entropy: bytes)
    }
}
