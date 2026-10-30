/// A service that creates recovery phrases, derives accounts and keys, and signs messages.
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

    public func recoveryPhrase(wordCount: RecoveryPhrase.WordCount) throws -> RecoveryPhrase {
        let bytes = try entropy.bytes(count: wordCount.entropyByteCount)
        guard bytes.count == wordCount.entropyByteCount else {
            throw RecoveryPhrase.ValidationError.invalidEntropy
        }
        return try RecoveryPhrase(entropy: bytes)
    }
}
