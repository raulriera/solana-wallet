import CryptoKit

/// Hardened SLIP-0010 Ed25519 key derivation.
enum KeyDerivation {
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
        for index in path.indices {
            try Task.checkCancellation()
            let child = index | 0x8000_0000
            let indexBytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: child >> $0) }
            let data = [0] + Array(node.prefix(32)) + indexBytes
            node = Array(HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: node.suffix(32))))
        }
        return Array(node.prefix(32))
    }
}
