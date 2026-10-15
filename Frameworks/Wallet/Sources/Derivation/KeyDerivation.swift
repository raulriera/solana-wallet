import CryptoKit

/// Hardened SLIP-0010 Ed25519 key derivation.
enum KeyDerivation {
    /// Recovers a CryptoKit signing key using the wallet's standard derivation pipeline.
    ///
    /// - Parameters:
    ///   - phrase: The validated recovery words.
    ///   - passphrase: The original BIP-39 passphrase.
    ///   - path: The hardened account path.
    /// - Returns: An Ed25519 key for use only within the current operation.
    /// - Throws: `CancellationError` if cancelled, or a cryptographic error.
    static func signingKey(
        for phrase: RecoveryPhrase, passphrase: String, path: DerivationPath
    ) throws -> Curve25519.Signing.PrivateKey {
        var seed = try SeedDerivation.seed(for: phrase, passphrase: passphrase)
        defer { seed.erase() }
        return try signingKey(seed: seed, path: path)
    }

    /// Recovers a CryptoKit signing key from a seed that the caller already derived.
    ///
    /// - Parameters:
    ///   - seed: The BIP-39 seed bytes.
    ///   - path: The hardened account path.
    /// - Returns: An Ed25519 key for use only within the current operation.
    /// - Throws: `CancellationError` if cancelled, or a cryptographic error.
    static func signingKey(seed: [UInt8], path: DerivationPath) throws -> Curve25519.Signing.PrivateKey {
        var bytes = try privateKey(seed: seed, path: path)
        defer { bytes.erase() }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: bytes)
    }

    /// Derives the Ed25519 private key at a hardened path.
    ///
    /// - Parameters:
    ///   - seed: The BIP-39 seed bytes.
    ///   - path: The hardened child indices to derive.
    /// - Returns: The 32-byte private key seed accepted by CryptoKit.
    /// - Throws: `CancellationError` if cancelled.
    static func privateKey(seed: [UInt8], path: DerivationPath) throws -> [UInt8] {
        try Task.checkCancellation()
        var node = Array(HMAC<SHA512>.authenticationCode(
            for: seed, using: SymmetricKey(data: Array("ed25519 seed".utf8))
        ))
        defer { node.erase() }
        for index in path.indices {
            try Task.checkCancellation()
            let child = index | 0x8000_0000
            let indexBytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: child >> $0) }
            var data = [0] + Array(node.prefix(32)) + indexBytes
            defer { data.erase() }
            node = Array(HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: node.suffix(32))))
        }
        return Array(node.prefix(32))
    }
}
