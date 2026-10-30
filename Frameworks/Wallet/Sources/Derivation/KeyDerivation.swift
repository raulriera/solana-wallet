import CryptoKit

/// Hardened SLIP-0010 key derivation on Ed25519.
enum KeyDerivation {
    private static let masterHMACKey = SymmetricKey(data: Array("ed25519 seed".utf8))

    /// Derives the Ed25519 signing key at a hardened path.
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

    /// Derives the private key at a hardened path.
    ///
    /// - Parameters:
    ///   - seed: The BIP-39 seed bytes.
    ///   - path: The hardened child indices to derive.
    /// - Returns: The 32-byte Ed25519 private key seed.
    /// - Throws: `CancellationError` if cancelled.
    static func privateKey(seed: [UInt8], path: DerivationPath) throws -> [UInt8] {
        var (key, chainCode) = try node(seed: seed, path: path)
        chainCode.erase()
        return key
    }

    /// Derives the private key and chain code at a hardened path.
    ///
    /// - Parameters:
    ///   - seed: The BIP-39 seed bytes.
    ///   - path: The hardened child indices to derive.
    /// - Returns: The 32-byte private key and the 32-byte chain code at `path`.
    /// - Throws: `CancellationError` if cancelled.
    static func node(seed: [UInt8], path: DerivationPath) throws -> (key: [UInt8], chainCode: [UInt8]) {
        try Task.checkCancellation()
        var node = Array(HMAC<SHA512>.authenticationCode(for: seed, using: masterHMACKey))
        defer { node.erase() }
        for hardenedIndex in path.hardenedIndices {
            try Task.checkCancellation()
            var message = childMessage(parent: node.prefix(32), index: hardenedIndex)
            defer { message.erase() }
            let child = Array(HMAC<SHA512>.authenticationCode(for: message, using: SymmetricKey(data: node.suffix(32))))
            node.erase()
            node = child
        }
        return (Array(node.prefix(32)), Array(node.suffix(32)))
    }

    /// Builds a hardened child's HMAC message in one buffer.
    ///
    /// - Parameters:
    ///   - parent: The parent's private key.
    ///   - index: The hardened child index.
    /// - Returns: `0x00 || parent || ser32(index)`, with the index big-endian.
    private static func childMessage(parent: ArraySlice<UInt8>, index: UInt32) -> [UInt8] {
        var message = [UInt8]()
        message.reserveCapacity(1 + parent.count + MemoryLayout<UInt32>.size)
        message.append(0)
        message.append(contentsOf: parent)
        withUnsafeBytes(of: index.bigEndian) { message.append(contentsOf: $0) }
        return message
    }
}
