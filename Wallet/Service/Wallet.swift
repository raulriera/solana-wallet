import CryptoKit

/// A service that creates recovery phrases and derives Solana addresses without networking or persistence.
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
    /// - Parameter wordCount: The number of words to generate. The default is twelve.
    /// - Returns: An English BIP-39 recovery phrase for the caller to back up.
    /// - Throws: An error if the entropy source fails or returns an invalid byte count.
    public func recoveryPhrase(wordCount: RecoveryPhrase.WordCount = .twelve) throws -> RecoveryPhrase {
        let bytes = try entropy.bytes(count: wordCount.entropyByteCount)
        guard bytes.count == wordCount.entropyByteCount else {
            throw RecoveryPhrase.ValidationError.invalidEntropy
        }
        return try RecoveryPhrase(entropy: bytes)
    }

    /// Derives a Solana address on the concurrent executor.
    ///
    /// The service doesn't retain the phrase, passphrase, or derived private key.
    /// Importing an existing account requires its original passphrase and path;
    /// this operation doesn't discover accounts or check their network activity.
    ///
    /// - Parameters:
    ///   - phrase: The validated recovery phrase.
    ///   - passphrase: The optional BIP-39 passphrase. Whitespace and case are significant.
    ///   - path: The hardened path. The default is `m/44'/501'/0'/0'`.
    /// - Returns: The Base58-encoded public address, shared across Solana networks.
    /// - Throws: `CancellationError` if cancelled, or a cryptographic error.
    @concurrent
    public func address(
        for phrase: RecoveryPhrase,
        passphrase: String = "",
        path: DerivationPath = .solana
    ) async throws -> String {
        try Task.checkCancellation()
        let seed = try SeedDerivation.seed(for: phrase, passphrase: passphrase)
        let privateKey = try KeyDerivation.privateKey(seed: seed, path: path)
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey)
        let address = Base58.encode(Array(key.publicKey.rawRepresentation))
        try Task.checkCancellation()
        return address
    }
}
