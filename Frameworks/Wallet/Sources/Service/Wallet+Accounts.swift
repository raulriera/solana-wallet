import CryptoKit
import Encoding

extension Wallet {
    /// Derives multiple accounts on the concurrent executor using one temporary BIP-39 seed.
    ///
    /// No phrase, passphrase, seed, or private key is retained by the service.
    /// An empty path list returns an empty result without deriving a seed.
    /// - Parameters:
    ///   - phrase: The validated recovery words.
    ///   - passphrase: The original BIP-39 passphrase, including significant whitespace.
    ///   - paths: Hardened paths in the desired order, including any duplicates.
    /// - Returns: The corresponding public addresses and exact paths.
    /// - Throws: A cryptographic error or `CancellationError`.
    @concurrent
    public func accounts(for phrase: RecoveryPhrase, passphrase: String = "",
                         paths: [DerivationPath]) async throws -> [DerivedAccount] {
        try Task.checkCancellation()
        guard !paths.isEmpty else { return [] }
        let seed = try SeedDerivation.seed(for: phrase, passphrase: passphrase)
        let accounts = try paths.map { path in
            let bytes = try KeyDerivation.privateKey(seed: seed, path: path)
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: bytes)
            return DerivedAccount(address: Base58.encode(Array(key.publicKey.rawRepresentation)), path: path)
        }
        try Task.checkCancellation()
        return accounts
    }
}
