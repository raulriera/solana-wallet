import CryptoKit
import Encoding

extension Wallet {
    /// Recovers an account from one temporary seed after checking it against the intended address.
    ///
    /// Signing and private-balance keys share this check. A malformed address fails before the seed
    /// is derived. The seed is erased when `body` returns.
    ///
    /// - Parameters:
    ///   - phrase: The validated recovery words.
    ///   - passphrase: The original BIP-39 passphrase.
    ///   - path: The account's hardened path.
    ///   - expectedAddress: The exact Base58 address that the recovered key must match.
    ///   - mismatch: The error to throw if the address is malformed or belongs to another account.
    ///   - body: Work that uses the account's signing key and the seed, within the current operation.
    /// - Returns: The result of `body`.
    /// - Throws: `mismatch`, `CancellationError` if cancelled, a cryptographic error, or an error
    ///   from `body`.
    static func withVerifiedAccount<Value>(
        _ phrase: RecoveryPhrase,
        passphrase: String,
        path: DerivationPath,
        expectedAddress: String,
        mismatch: some Error,
        _ body: (_ key: Curve25519.Signing.PrivateKey, _ seed: [UInt8]) throws -> Value
    ) throws -> Value {
        guard let expectedKey = Base58.decode(expectedAddress, byteCount: 32) else { throw mismatch }
        var seed = try SeedDerivation.seed(for: phrase, passphrase: passphrase)
        defer { seed.erase() }
        let key = try KeyDerivation.signingKey(seed: seed, path: path)
        guard Array(key.publicKey.rawRepresentation) == expectedKey else { throw mismatch }
        return try body(key, seed)
    }
}
