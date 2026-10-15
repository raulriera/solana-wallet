import CryptoKit

/// Hardened SLIP-0010 key derivation for every supported curve.
enum KeyDerivation {
    /// Derives the Ed25519 signing key at a hardened path.
    ///
    /// - Parameters:
    ///   - seed: The BIP-39 seed bytes.
    ///   - path: The hardened account path.
    /// - Returns: An Ed25519 key for use only within the current operation.
    /// - Throws: `CancellationError` if cancelled, or a cryptographic error.
    static func signingKey(seed: [UInt8], path: DerivationPath) throws -> Curve25519.Signing.PrivateKey {
        var bytes = try privateKey(seed: seed, path: path, curve: .ed25519)
        defer { bytes.erase() }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: bytes)
    }

    /// Derives the private key at a hardened path.
    ///
    /// - Parameters:
    ///   - seed: The BIP-39 seed bytes.
    ///   - path: The hardened child indices to derive.
    ///   - curve: The curve whose SLIP-0010 rules accept each key.
    /// - Returns: The 32-byte private key: an Ed25519 private key seed, or a big-endian P-256 scalar.
    /// - Throws: `CancellationError` if cancelled.
    static func privateKey(seed: [UInt8], path: DerivationPath, curve: some DerivationCurve) throws -> [UInt8] {
        var (key, chainCode) = try node(seed: seed, path: path, curve: curve)
        chainCode.erase()
        return key
    }

    /// Derives the private key and chain code at a hardened path.
    ///
    /// SLIP-0010 hashes again whenever the curve refuses a candidate key. The master key hashes the
    /// refused output with the curve's label; a child hashes `0x01 || I_R || ser32(index)` with the
    /// parent's chain code.
    ///
    /// - Parameters:
    ///   - seed: The BIP-39 seed bytes.
    ///   - path: The hardened child indices to derive.
    ///   - curve: The curve whose SLIP-0010 rules accept each key.
    /// - Returns: The 32-byte private key and the 32-byte chain code at `path`.
    /// - Throws: `CancellationError` if cancelled.
    static func node(
        seed: [UInt8], path: DerivationPath, curve: some DerivationCurve
    ) throws -> (key: [UInt8], chainCode: [UInt8]) {
        try Task.checkCancellation()
        // The current private key followed by its chain code.
        var node = acceptedNode(
            hashing: seed, using: SymmetricKey(data: Array(curve.label.utf8)), parent: nil, curve: curve
        ) { refused in refused }
        defer { node.erase() }
        for hardenedIndex in path.hardenedIndices {
            try Task.checkCancellation()
            let indexBytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: hardenedIndex >> $0) }
            var parent = Array(node.prefix(32))
            defer { parent.erase() }
            let child = acceptedNode(
                hashing: childMessage(0, parent, indexBytes), using: SymmetricKey(data: node.suffix(32)),
                parent: parent, curve: curve
            ) { refused in childMessage(1, refused.suffix(32), indexBytes) }
            node.erase()
            node = child
        }
        return (Array(node.prefix(32)), Array(node.suffix(32)))
    }

    /// Builds a child's HMAC message in one buffer, so that no partial copy of the secret bytes
    /// is released without being erased.
    ///
    /// - Parameters:
    ///   - marker: `0x00` before the parent's private key, or `0x01` before a refused output's I_R.
    ///   - secret: The parent's private key, or the refused output's I_R.
    ///   - indexBytes: The hardened child index as a big-endian `ser32` value.
    /// - Returns: `marker || secret || indexBytes`.
    private static func childMessage(
        _ marker: UInt8, _ secret: some Collection<UInt8>, _ indexBytes: [UInt8]
    ) -> [UInt8] {
        var message = [UInt8]()
        message.reserveCapacity(1 + secret.count + indexBytes.count)
        message.append(marker)
        message.append(contentsOf: secret)
        message.append(contentsOf: indexBytes)
        return message
    }

    /// Hashes until the curve accepts the left half of an output as a private key.
    ///
    /// - Parameters:
    ///   - message: The first message to hash.
    ///   - hmacKey: The HMAC-SHA512 key: the curve's label, or the parent's chain code.
    ///   - parent: The parent's private key, or `nil` for the master key.
    ///   - curve: The curve whose rule accepts or refuses each candidate.
    ///   - nextMessage: The message to hash after the curve refuses an output.
    /// - Returns: The accepted private key followed by the right half of its output, the chain code.
    private static func acceptedNode(
        hashing message: consuming [UInt8],
        using hmacKey: SymmetricKey,
        parent: [UInt8]?,
        curve: some DerivationCurve,
        retrying nextMessage: (_ refused: [UInt8]) -> [UInt8]
    ) -> [UInt8] {
        defer { message.erase() }
        while true {
            var output = Array(HMAC<SHA512>.authenticationCode(for: message, using: hmacKey))
            defer { output.erase() }
            var candidate = Array(output.prefix(32))
            defer { candidate.erase() }
            if var key = curve.privateKey(candidate: candidate, parent: parent) {
                defer { key.erase() }
                return key + output.suffix(32)
            }
            message.erase()
            message = nextMessage(output)
        }
    }
}
